import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/backlog/pm — Overdue and unscheduled preventive maintenance
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT ps.pm_id, ps.name, ps.description, ps.schedule_type,
                    ps.interval_value, ps.interval_unit,
                    ps.next_due_date, ps.next_due_meter,
                    a.name AS asset_name, a.tag_number,
                    CASE 
                        WHEN ps.next_due_date IS NULL THEN 'Unscheduled'
                        WHEN ps.next_due_date < NOW() THEN 'Overdue'
                        ELSE 'Scheduled'
                    END AS pm_status,
                    CASE WHEN ps.next_due_date < NOW() THEN
                        EXTRACT(EPOCH FROM (NOW() - ps.next_due_date)) / 86400
                    ELSE NULL END AS days_overdue
             FROM maintenance.preventive_schedule ps
             LEFT JOIN assets.registry a ON ps.asset_id = a.asset_id
             WHERE ps.tenant_id = $1 AND ps.is_active = true
               AND (ps.next_due_date < NOW() OR ps.next_due_date IS NULL)
             ORDER BY ps.next_due_date ASC NULLS LAST`,
            [user.tenantId]
        );

        return NextResponse.json({ data: result.rows, count: result.rowCount });
    } catch (error: any) {
        console.error('Backlog PM error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
