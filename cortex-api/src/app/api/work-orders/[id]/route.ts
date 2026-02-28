import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/work-orders/[id] — Get a single work order with full JOINs
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const result = await db.query(
            `SELECT w.*,
                    a.name AS asset_name, a.tag_number,
                    l.name AS location_name,
                    rep.first_name || ' ' || rep.last_name AS reported_by,
                    asgn.first_name || ' ' || asgn.last_name AS assigned_to,
                    ps.name AS pm_name
             FROM maintenance.work_orders w
             LEFT JOIN assets.registry a ON w.asset_id = a.asset_id
             LEFT JOIN core.locations l ON w.location_id = l.location_id
             LEFT JOIN core.users rep ON w.reported_by_id = rep.user_id
             LEFT JOIN core.users asgn ON w.assigned_to_id = asgn.user_id
             LEFT JOIN maintenance.preventive_schedule ps ON w.pm_id = ps.pm_id
             WHERE w.wo_id = $1 AND w.tenant_id = $2`,
            [id, user.tenantId]
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'Work order not found' }, { status: 404 });
        }

        return NextResponse.json({ data: result.rows[0] });
    } catch (error: any) {
        console.error('WO GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// PUT /api/work-orders/[id] — Update a work order
export async function PUT(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const body = await req.json();

        const allowedFields: Record<string, string> = {
            title: 'title', description: 'description', type: 'type',
            priority: 'priority', status: 'status',
            assetId: 'asset_id', asset_id: 'asset_id',
            locationId: 'location_id', location_id: 'location_id',
            assignedToId: 'assigned_to_id', assigned_to_id: 'assigned_to_id',
            pmId: 'pm_id', pm_id: 'pm_id',
            dueDate: 'due_date', due_date: 'due_date',
            startTime: 'start_time', start_time: 'start_time',
            completionTime: 'completion_time', completion_time: 'completion_time',
            laborCost: 'labor_cost', labor_cost: 'labor_cost',
            materialCost: 'material_cost', material_cost: 'material_cost'
        };

        const setClauses: string[] = [];
        const values: any[] = [];
        let paramIdx = 1;

        for (const [key, col] of Object.entries(allowedFields)) {
            if (body[key] !== undefined) {
                setClauses.push(`${col} = $${paramIdx}`);
                values.push(body[key]);
                paramIdx++;
            }
        }

        if (setClauses.length === 0) {
            return NextResponse.json({ error: 'No valid fields to update' }, { status: 400 });
        }

        values.push(id, user.tenantId);
        const result = await db.query(
            `UPDATE maintenance.work_orders SET ${setClauses.join(', ')}
             WHERE wo_id = $${paramIdx} AND tenant_id = $${paramIdx + 1}
             RETURNING *`,
            values
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'Work order not found' }, { status: 404 });
        }

        return NextResponse.json({ message: 'Work order updated', data: result.rows[0] });
    } catch (error: any) {
        console.error('WO PUT error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// DELETE /api/work-orders/[id] — Delete a work order
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const result = await db.query(
            'DELETE FROM maintenance.work_orders WHERE wo_id = $1 AND tenant_id = $2 RETURNING wo_id',
            [id, user.tenantId]
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'Work order not found' }, { status: 404 });
        }

        return NextResponse.json({ message: 'Work order deleted' });
    } catch (error: any) {
        if (error.code === '23503') {
            return NextResponse.json({ error: 'Cannot delete — work order has linked tasks or part usage' }, { status: 409 });
        }
        console.error('WO DELETE error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
