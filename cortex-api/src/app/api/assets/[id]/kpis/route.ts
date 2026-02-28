import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets/[id]/kpis — All KPIs for a single asset
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const { searchParams } = new URL(req.url);
        const startDate = searchParams.get('start_date') || '1970-01-01';
        const endDate = searchParams.get('end_date') || new Date().toISOString().split('T')[0];

        // Verify asset belongs to tenant
        const asset = await db.query(
            'SELECT asset_id, name, tag_number, install_date FROM assets.registry WHERE asset_id = $1 AND tenant_id = $2',
            [id, user.tenantId]
        );
        if (asset.rowCount === null || asset.rowCount === 0) {
            return NextResponse.json({ error: 'Asset not found' }, { status: 404 });
        }

        // Get downtime events in date range
        const downtime = await db.query(
            `SELECT event_id, started_at, ended_at, reason,
                    EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 3600 AS duration_hours
             FROM assets.downtime_events
             WHERE asset_id = $1 AND tenant_id = $2
               AND started_at >= $3 AND started_at <= $4
             ORDER BY started_at`,
            [id, user.tenantId, startDate, endDate]
        );

        // Get completed work orders for this asset
        const workOrders = await db.query(
            `SELECT wo_id, start_time, completion_time,
                    EXTRACT(EPOCH FROM (completion_time - start_time)) / 3600 AS repair_hours
             FROM maintenance.work_orders
             WHERE asset_id = $1 AND tenant_id = $2 AND status = 'Complete'
               AND completion_time IS NOT NULL AND start_time IS NOT NULL
               AND requested_date >= $3 AND requested_date <= $4`,
            [id, user.tenantId, startDate, endDate]
        );

        const totalDowntimeHrs = downtime.rows.reduce((sum: number, r: any) => sum + parseFloat(r.duration_hours || 0), 0);
        const breakdownEvents = downtime.rows.filter((r: any) => r.reason === 'Breakdown');
        const breakdownCount = breakdownEvents.length;

        // MTTR: Mean Time To Repair (avg repair duration from completed WOs)
        const repairHours = workOrders.rows.map((r: any) => parseFloat(r.repair_hours || 0)).filter((h: number) => h > 0);
        const mttr = repairHours.length > 0 ? repairHours.reduce((a: number, b: number) => a + b, 0) / repairHours.length : 0;

        // Period total hours
        const periodStart = new Date(startDate);
        const periodEnd = new Date(endDate);
        const totalPeriodHrs = Math.max((periodEnd.getTime() - periodStart.getTime()) / (1000 * 3600), 1);

        // MTBF: Mean Time Between Failures
        const uptimeHrs = totalPeriodHrs - totalDowntimeHrs;
        const mtbf = breakdownCount > 1 ? uptimeHrs / breakdownCount : uptimeHrs;

        // Availability: uptime / total period
        const availability = Math.max(0, Math.min(100, ((totalPeriodHrs - totalDowntimeHrs) / totalPeriodHrs) * 100));

        return NextResponse.json({
            data: {
                asset: asset.rows[0],
                period: { start: startDate, end: endDate, totalHours: Math.round(totalPeriodHrs * 100) / 100 },
                mttr: { value: Math.round(mttr * 100) / 100, unit: 'hours', repairCount: repairHours.length },
                mtbf: { value: Math.round(mtbf * 100) / 100, unit: 'hours', breakdownCount },
                availability: { value: Math.round(availability * 100) / 100, unit: '%' },
                downtime: {
                    totalHours: Math.round(totalDowntimeHrs * 100) / 100,
                    eventCount: downtime.rowCount,
                    breakdownCount,
                    byReason: groupBy(downtime.rows, 'reason')
                },
                workOrders: { completedCount: workOrders.rowCount }
            }
        });
    } catch (error: any) {
        console.error('KPIs error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

function groupBy(rows: any[], key: string): Record<string, number> {
    return rows.reduce((acc: Record<string, number>, row: any) => {
        acc[row[key]] = (acc[row[key]] || 0) + 1;
        return acc;
    }, {});
}
