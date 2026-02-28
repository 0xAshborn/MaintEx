import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets/[id]/mtbf — Mean Time Between Failures
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;

        // Get the asset's install date as the start of the observation period
        const asset = await db.query(
            'SELECT install_date FROM assets.registry WHERE asset_id = $1 AND tenant_id = $2',
            [id, user.tenantId]
        );
        if (asset.rowCount === null || asset.rowCount === 0) {
            return NextResponse.json({ error: 'Asset not found' }, { status: 404 });
        }

        const installDate = asset.rows[0].install_date || '2024-01-01';
        const now = new Date();
        const totalHours = (now.getTime() - new Date(installDate).getTime()) / (1000 * 3600);

        // Count breakdown events and total downtime
        const result = await db.query(
            `SELECT 
                COUNT(*) AS breakdown_count,
                COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 3600), 0) AS total_downtime_hours
             FROM assets.downtime_events
             WHERE asset_id = $1 AND tenant_id = $2 AND reason = 'Breakdown'`,
            [id, user.tenantId]
        );

        const row = result.rows[0];
        const breakdownCount = parseInt(row.breakdown_count);
        const uptimeHours = Math.max(0, totalHours - parseFloat(row.total_downtime_hours));
        const mtbf = breakdownCount > 0 ? uptimeHours / breakdownCount : uptimeHours;

        return NextResponse.json({
            data: {
                mtbf: Math.round(mtbf * 100) / 100,
                unit: 'hours',
                breakdownCount,
                totalUptimeHours: Math.round(uptimeHours * 100) / 100,
                observationPeriodHours: Math.round(totalHours * 100) / 100
            }
        });
    } catch (error: any) {
        console.error('MTBF error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
