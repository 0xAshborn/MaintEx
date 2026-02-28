import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/backlog/aging — Backlog by age buckets
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT
                CASE
                    WHEN EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400 <= 7 THEN '0-7 days'
                    WHEN EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400 <= 14 THEN '8-14 days'
                    WHEN EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400 <= 30 THEN '15-30 days'
                    WHEN EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400 <= 60 THEN '31-60 days'
                    WHEN EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400 <= 90 THEN '61-90 days'
                    ELSE '90+ days'
                END AS age_bucket,
                COUNT(*) AS count,
                COUNT(*) FILTER (WHERE priority IN ('Urgent', 'High')) AS high_priority
             FROM maintenance.work_orders
             WHERE tenant_id = $1 AND status NOT IN ('Complete')
             GROUP BY age_bucket
             ORDER BY
                CASE age_bucket
                    WHEN '0-7 days' THEN 1 WHEN '8-14 days' THEN 2
                    WHEN '15-30 days' THEN 3 WHEN '31-60 days' THEN 4
                    WHEN '61-90 days' THEN 5 ELSE 6
                END`,
            [user.tenantId]
        );

        return NextResponse.json({
            data: result.rows.map((r: any) => ({
                ageBucket: r.age_bucket,
                count: parseInt(r.count),
                highPriority: parseInt(r.high_priority)
            }))
        });
    } catch (error: any) {
        console.error('Backlog aging error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
