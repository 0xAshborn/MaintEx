import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets/[id]/oee — Overall Equipment Effectiveness
// OEE = Availability × Performance × Quality
// Availability is computed from downtime. Performance and Quality are provided as query params
// (since they require production data not captured in the CMMS).
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const { searchParams } = new URL(req.url);
        const performance = parseFloat(searchParams.get('performance') || '100'); // % default 100
        const quality = parseFloat(searchParams.get('quality') || '100');         // % default 100
        const startDate = searchParams.get('start_date') || '1970-01-01';
        const endDate = searchParams.get('end_date') || new Date().toISOString().split('T')[0];

        const periodStart = new Date(startDate);
        const periodEnd = new Date(endDate);
        const totalPeriodHrs = Math.max((periodEnd.getTime() - periodStart.getTime()) / (1000 * 3600), 1);

        // Compute availability from downtime
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
        const availability = Math.max(0, ((totalPeriodHrs - downtimeHrs) / totalPeriodHrs) * 100);

        const oee = (availability / 100) * (performance / 100) * (quality / 100) * 100;

        return NextResponse.json({
            data: {
                oee: Math.round(oee * 100) / 100,
                unit: '%',
                factors: {
                    availability: Math.round(availability * 100) / 100,
                    performance: Math.round(performance * 100) / 100,
                    quality: Math.round(quality * 100) / 100
                },
                period: { start: startDate, end: endDate },
                classification: oee >= 85 ? 'World Class' : oee >= 60 ? 'Acceptable' : 'Needs Improvement'
            }
        });
    } catch (error: any) {
        console.error('OEE error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
