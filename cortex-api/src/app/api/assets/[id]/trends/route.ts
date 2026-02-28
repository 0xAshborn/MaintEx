import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets/[id]/trends — Downtime and repair trends over time
// Query params: ?period=30&interval=week
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const { searchParams } = new URL(req.url);
        const period = parseInt(searchParams.get('period') || '90'); // days
        const interval = searchParams.get('interval') || 'week'; // 'day', 'week', 'month'

        const truncUnit = interval === 'day' ? 'day' : interval === 'month' ? 'month' : 'week';

        // Downtime trends
        const downtimeTrends = await db.query(
            `SELECT 
                DATE_TRUNC($1, started_at) AS period_start,
                COUNT(*) AS event_count,
                COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 3600), 0) AS total_hours
             FROM assets.downtime_events
             WHERE asset_id = $2 AND tenant_id = $3
               AND started_at >= NOW() - ($4 || ' days')::INTERVAL
             GROUP BY DATE_TRUNC($1, started_at)
             ORDER BY period_start`,
            [truncUnit, id, user.tenantId, period.toString()]
        );

        // Work order trends
        const woTrends = await db.query(
            `SELECT 
                DATE_TRUNC($1, requested_date) AS period_start,
                COUNT(*) AS wo_count,
                COUNT(*) FILTER (WHERE status = 'Complete') AS completed_count,
                COALESCE(AVG(EXTRACT(EPOCH FROM (completion_time - start_time)) / 3600) 
                    FILTER (WHERE status = 'Complete' AND completion_time IS NOT NULL AND start_time IS NOT NULL), 0) AS avg_repair_hours
             FROM maintenance.work_orders
             WHERE asset_id = $2 AND tenant_id = $3
               AND requested_date >= NOW() - ($4 || ' days')::INTERVAL
             GROUP BY DATE_TRUNC($1, requested_date)
             ORDER BY period_start`,
            [truncUnit, id, user.tenantId, period.toString()]
        );

        return NextResponse.json({
            data: {
                period: { days: period, interval },
                downtime: downtimeTrends.rows.map((r: any) => ({
                    period: r.period_start,
                    events: parseInt(r.event_count),
                    totalHours: Math.round(parseFloat(r.total_hours) * 100) / 100
                })),
                workOrders: woTrends.rows.map((r: any) => ({
                    period: r.period_start,
                    total: parseInt(r.wo_count),
                    completed: parseInt(r.completed_count),
                    avgRepairHours: Math.round(parseFloat(r.avg_repair_hours) * 100) / 100
                }))
            }
        });
    } catch (error: any) {
        console.error('Trends error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
