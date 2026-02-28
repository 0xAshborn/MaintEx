import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/backlog/by-asset — Backlog grouped by asset
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT a.asset_id, a.name AS asset_name, a.tag_number, a.criticality,
                    COUNT(w.wo_id) AS wo_count,
                    COUNT(w.wo_id) FILTER (WHERE w.due_date < NOW()) AS overdue,
                    COUNT(w.wo_id) FILTER (WHERE w.priority IN ('Urgent', 'High')) AS high_priority,
                    COALESCE(AVG(EXTRACT(EPOCH FROM (NOW() - w.requested_date)) / 86400), 0) AS avg_age_days
             FROM maintenance.work_orders w
             JOIN assets.registry a ON w.asset_id = a.asset_id
             WHERE w.tenant_id = $1 AND w.status NOT IN ('Complete')
             GROUP BY a.asset_id, a.name, a.tag_number, a.criticality
             ORDER BY COUNT(w.wo_id) DESC`,
            [user.tenantId]
        );

        return NextResponse.json({
            data: result.rows.map((r: any) => ({
                assetId: r.asset_id,
                assetName: r.asset_name,
                tagNumber: r.tag_number,
                criticality: r.criticality,
                woCount: parseInt(r.wo_count),
                overdue: parseInt(r.overdue),
                highPriority: parseInt(r.high_priority),
                avgAgeDays: Math.round(parseFloat(r.avg_age_days) * 10) / 10
            }))
        });
    } catch (error: any) {
        console.error('Backlog by-asset error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
