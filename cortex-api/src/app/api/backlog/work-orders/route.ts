import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/backlog/work-orders — List all non-complete work orders
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT w.wo_id, w.title, w.type, w.priority, w.status,
                    w.due_date, w.requested_date, w.assigned_to_id,
                    a.name AS asset_name, a.tag_number,
                    l.name AS location_name,
                    u.first_name || ' ' || u.last_name AS assigned_to,
                    EXTRACT(EPOCH FROM (NOW() - w.requested_date)) / 86400 AS age_days,
                    CASE WHEN w.due_date < NOW() THEN true ELSE false END AS is_overdue
             FROM maintenance.work_orders w
             LEFT JOIN assets.registry a ON w.asset_id = a.asset_id
             LEFT JOIN core.locations l ON w.location_id = l.location_id
             LEFT JOIN core.users u ON w.assigned_to_id = u.user_id
             WHERE w.tenant_id = $1 AND w.status NOT IN ('Complete')
             ORDER BY
                CASE w.priority WHEN 'Urgent' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4 END,
                w.due_date ASC NULLS LAST`,
            [user.tenantId]
        );

        return NextResponse.json({ data: result.rows, count: result.rowCount });
    } catch (error: any) {
        console.error('Backlog WOs error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
