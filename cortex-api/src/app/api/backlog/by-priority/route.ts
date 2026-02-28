import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/backlog/by-priority — Backlog grouped by priority
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT priority,
                    COUNT(*) AS count,
                    COUNT(*) FILTER (WHERE due_date < NOW()) AS overdue,
                    COALESCE(AVG(EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400), 0) AS avg_age_days
             FROM maintenance.work_orders
             WHERE tenant_id = $1 AND status NOT IN ('Complete')
             GROUP BY priority
             ORDER BY CASE priority WHEN 'Urgent' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4 END`,
            [user.tenantId]
        );

        return NextResponse.json({
            data: result.rows.map((r: any) => ({
                priority: r.priority,
                count: parseInt(r.count),
                overdue: parseInt(r.overdue),
                avgAgeDays: Math.round(parseFloat(r.avg_age_days) * 10) / 10
            }))
        });
    } catch (error: any) {
        console.error('Backlog by-priority error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
