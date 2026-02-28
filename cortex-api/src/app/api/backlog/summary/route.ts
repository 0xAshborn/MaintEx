import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/backlog/summary — Overview of open/overdue WOs and PMs
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT
                COUNT(*) FILTER (WHERE status IN ('Open', 'In Progress', 'On Hold', 'Draft')) AS total_open,
                COUNT(*) FILTER (WHERE status = 'Open') AS open,
                COUNT(*) FILTER (WHERE status = 'In Progress') AS in_progress,
                COUNT(*) FILTER (WHERE status = 'On Hold') AS on_hold,
                COUNT(*) FILTER (WHERE status = 'Draft') AS draft,
                COUNT(*) FILTER (WHERE due_date < NOW() AND status NOT IN ('Complete')) AS overdue,
                COUNT(*) FILTER (WHERE due_date >= NOW() AND due_date < NOW() + INTERVAL '7 days' AND status NOT IN ('Complete')) AS due_this_week,
                COUNT(*) FILTER (WHERE priority = 'Urgent' AND status NOT IN ('Complete')) AS urgent,
                COUNT(*) FILTER (WHERE priority = 'High' AND status NOT IN ('Complete')) AS high_priority,
                COALESCE(AVG(EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400) FILTER (WHERE status NOT IN ('Complete')), 0) AS avg_age_days
             FROM maintenance.work_orders
             WHERE tenant_id = $1`,
            [user.tenantId]
        );

        const pmResult = await db.query(
            `SELECT
                COUNT(*) AS total_active,
                COUNT(*) FILTER (WHERE next_due_date < NOW()) AS overdue,
                COUNT(*) FILTER (WHERE next_due_date IS NULL) AS unscheduled
             FROM maintenance.preventive_schedule
             WHERE tenant_id = $1 AND is_active = true`,
            [user.tenantId]
        );

        const row = result.rows[0];
        const pm = pmResult.rows[0];
        return NextResponse.json({
            data: {
                workOrders: {
                    totalOpen: parseInt(row.total_open),
                    open: parseInt(row.open),
                    inProgress: parseInt(row.in_progress),
                    onHold: parseInt(row.on_hold),
                    draft: parseInt(row.draft),
                    overdue: parseInt(row.overdue),
                    dueThisWeek: parseInt(row.due_this_week),
                    urgent: parseInt(row.urgent),
                    highPriority: parseInt(row.high_priority),
                    avgAgeDays: Math.round(parseFloat(row.avg_age_days) * 10) / 10
                },
                preventiveMaintenance: {
                    totalActive: parseInt(pm.total_active),
                    overdue: parseInt(pm.overdue),
                    unscheduled: parseInt(pm.unscheduled)
                }
            }
        });
    } catch (error: any) {
        console.error('Backlog summary error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
