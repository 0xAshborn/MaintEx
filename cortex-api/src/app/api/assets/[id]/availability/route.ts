import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets/[id]/availability — Uptime percentage
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const { searchParams } = new URL(req.url);
        const startDate = searchParams.get('start_date') || '1970-01-01';
        const endDate = searchParams.get('end_date') || new Date().toISOString().split('T')[0];

        const periodStart = new Date(startDate);
        const periodEnd = new Date(endDate);
        const totalPeriodHrs = Math.max((periodEnd.getTime() - periodStart.getTime()) / (1000 * 3600), 1);

        const result = await db.query(
            `SELECT COALESCE(SUM(
                EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 3600
             ), 0) AS total_downtime_hours
             FROM assets.downtime_events
             WHERE asset_id = $1 AND tenant_id = $2
               AND started_at >= $3 AND started_at <= $4`,
            [id, user.tenantId, startDate, endDate]
        );

        const downtimeHrs = parseFloat(result.rows[0].total_downtime_hours);
        const uptimeHrs = Math.max(0, totalPeriodHrs - downtimeHrs);
        const availability = (uptimeHrs / totalPeriodHrs) * 100;

        return NextResponse.json({
            data: {
                availability: Math.round(availability * 100) / 100,
                unit: '%',
                uptimeHours: Math.round(uptimeHrs * 100) / 100,
                downtimeHours: Math.round(downtimeHrs * 100) / 100,
                totalPeriodHours: Math.round(totalPeriodHrs * 100) / 100,
                period: { start: startDate, end: endDate }
            }
        });
    } catch (error: any) {
        console.error('Availability error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
