import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/work-orders — List all work orders for the authenticated tenant
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT w.*, 
              a.name AS asset_name, a.tag_number,
              l.name AS location_name,
              u1.first_name || ' ' || u1.last_name AS reported_by,
              u2.first_name || ' ' || u2.last_name AS assigned_to
       FROM maintenance.work_orders w
       LEFT JOIN assets.registry a ON w.asset_id = a.asset_id
       LEFT JOIN core.locations l ON w.location_id = l.location_id
       LEFT JOIN core.users u1 ON w.reported_by_id = u1.user_id
       LEFT JOIN core.users u2 ON w.assigned_to_id = u2.user_id
       WHERE w.tenant_id = $1
       ORDER BY w.wo_id DESC`,
            [user.tenantId]
        );
        return NextResponse.json({ data: result.rows, count: result.rowCount });
    } catch (error: any) {
        console.error('Work Orders GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// POST /api/work-orders — Create a new work order for the authenticated tenant
export async function POST(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const body = await req.json();
        const { title, description, type, assetId, locationId, assignedToId, priority, dueDate } = body;

        if (!title || !type) {
            return NextResponse.json({ error: 'Missing required fields: title, type' }, { status: 400 });
        }

        const result = await db.query(
            `INSERT INTO maintenance.work_orders 
        (tenant_id, title, description, type, asset_id, location_id, reported_by_id, assigned_to_id, priority, due_date)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING *`,
            [user.tenantId, title, description || null, type, assetId || null, locationId || null, user.userId, assignedToId || null, priority || 'Medium', dueDate || null]
        );

        return NextResponse.json({ message: 'Work order created', data: result.rows[0] }, { status: 201 });
    } catch (error: any) {
        console.error('Work Orders POST error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
