import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets/[id]/mttr — Mean Time To Repair
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;

        const result = await db.query(
            `SELECT 
                COUNT(*) AS repair_count,
                AVG(EXTRACT(EPOCH FROM (completion_time - start_time)) / 3600) AS avg_repair_hours,
                MIN(EXTRACT(EPOCH FROM (completion_time - start_time)) / 3600) AS min_repair_hours,
                MAX(EXTRACT(EPOCH FROM (completion_time - start_time)) / 3600) AS max_repair_hours
             FROM maintenance.work_orders
             WHERE asset_id = $1 AND tenant_id = $2 
               AND status = 'Complete'
               AND completion_time IS NOT NULL AND start_time IS NOT NULL`,
            [id, user.tenantId]
        );

        const row = result.rows[0];
        return NextResponse.json({
            data: {
                mttr: Math.round(parseFloat(row.avg_repair_hours || 0) * 100) / 100,
                unit: 'hours',
                repairCount: parseInt(row.repair_count),
                min: Math.round(parseFloat(row.min_repair_hours || 0) * 100) / 100,
                max: Math.round(parseFloat(row.max_repair_hours || 0) * 100) / 100
            }
        });
    } catch (error: any) {
        console.error('MTTR error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
