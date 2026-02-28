import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// POST /api/work-orders/[id]/complete — Transition WO to "Complete"
// Body (optional): { labor_cost, material_cost }
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;

        // Verify the WO exists
        const check = await db.query(
            'SELECT wo_id, status FROM maintenance.work_orders WHERE wo_id = $1 AND tenant_id = $2',
            [id, user.tenantId]
        );
        if (check.rowCount === null || check.rowCount === 0) {
            return NextResponse.json({ error: 'Work order not found' }, { status: 404 });
        }

        const currentStatus = check.rows[0].status;
        if (currentStatus === 'Complete') {
            return NextResponse.json({ error: 'Work order is already complete' }, { status: 409 });
        }

        // Parse optional costs from body
        let laborCost = null;
        let materialCost = null;
        try {
            const body = await req.json();
            laborCost = body.labor_cost ?? body.laborCost ?? null;
            materialCost = body.material_cost ?? body.materialCost ?? null;
        } catch {
            // Body is optional — no-op if empty
        }

        // Build the update query
        const setClauses = ["status = 'Complete'", "completion_time = NOW()"];
        const values: any[] = [id, user.tenantId];
        let paramIdx = 3;

        if (laborCost !== null) {
            setClauses.push(`labor_cost = $${paramIdx}`);
            values.push(laborCost);
            paramIdx++;
        }
        if (materialCost !== null) {
            setClauses.push(`material_cost = $${paramIdx}`);
            values.push(materialCost);
            paramIdx++;
        }

        const result = await db.query(
            `UPDATE maintenance.work_orders
             SET ${setClauses.join(', ')}
             WHERE wo_id = $1 AND tenant_id = $2
             RETURNING wo_id, title, status, start_time, completion_time, labor_cost, material_cost, total_cost`,
            values
        );

        return NextResponse.json({ message: 'Work order completed', data: result.rows[0] });
    } catch (error: any) {
        console.error('WO complete error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
