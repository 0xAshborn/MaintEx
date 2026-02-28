import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/backlog/trend — Backlog growth over time (weekly snapshots)
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { searchParams } = new URL(req.url);
        const weeks = parseInt(searchParams.get('weeks') || '12');

        // Created per week
        const created = await db.query(
            `SELECT DATE_TRUNC('week', requested_date) AS week,
                    COUNT(*) AS created
             FROM maintenance.work_orders
             WHERE tenant_id = $1
               AND requested_date >= NOW() - ($2 || ' weeks')::INTERVAL
             GROUP BY DATE_TRUNC('week', requested_date)
             ORDER BY week`,
            [user.tenantId, weeks.toString()]
        );

        // Completed per week
        const completed = await db.query(
            `SELECT DATE_TRUNC('week', completion_time) AS week,
                    COUNT(*) AS completed
             FROM maintenance.work_orders
             WHERE tenant_id = $1 AND status = 'Complete' AND completion_time IS NOT NULL
               AND completion_time >= NOW() - ($2 || ' weeks')::INTERVAL
             GROUP BY DATE_TRUNC('week', completion_time)
             ORDER BY week`,
            [user.tenantId, weeks.toString()]
        );

        // Merge into a single timeline
        const weekMap: Record<string, { created: number; completed: number }> = {};
        created.rows.forEach((r: any) => {
            const key = r.week;
            weekMap[key] = { created: parseInt(r.created), completed: 0 };
        });
        completed.rows.forEach((r: any) => {
            const key = r.week;
            if (!weekMap[key]) weekMap[key] = { created: 0, completed: 0 };
            weekMap[key].completed = parseInt(r.completed);
        });

        const trend = Object.entries(weekMap)
            .sort(([a], [b]) => new Date(a).getTime() - new Date(b).getTime())
            .map(([week, data]) => ({
                week,
                created: data.created,
                completed: data.completed,
                netChange: data.created - data.completed
            }));

        return NextResponse.json({
            data: {
                weeks,
                trend,
                totals: {
                    created: trend.reduce((s, t) => s + t.created, 0),
                    completed: trend.reduce((s, t) => s + t.completed, 0),
                    netChange: trend.reduce((s, t) => s + t.netChange, 0)
                }
            }
        });
    } catch (error: any) {
        console.error('Backlog trend error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
