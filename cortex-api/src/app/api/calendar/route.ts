import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/calendar — Fetch all PM work orders formatted for calendar display
// Supports optional query params: ?start=2026-01-01&end=2026-01-31&status=Open
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { searchParams } = new URL(req.url);
        const start = searchParams.get('start');  // ISO date string
        const end = searchParams.get('end');      // ISO date string
        const status = searchParams.get('status'); // Optional filter

        let query = `
      SELECT 
        w.wo_id AS id,
        w.title,
        w.description,
        w.type,
        w.priority,
        w.status,
        w.due_date,
        w.start_time,
        w.completion_time,
        w.requested_date,
        w.assigned_to_id,
        a.name AS asset_name,
        a.tag_number,
        l.name AS location_name,
        u.first_name || ' ' || u.last_name AS assigned_to,
        ps.name AS pm_name,
        ps.schedule_type,
        ps.interval_value,
        ps.interval_unit,
        ps.next_due_date AS pm_next_due
      FROM maintenance.work_orders w
      LEFT JOIN assets.registry a ON w.asset_id = a.asset_id
      LEFT JOIN core.locations l ON w.location_id = l.location_id
      LEFT JOIN core.users u ON w.assigned_to_id = u.user_id
      LEFT JOIN maintenance.preventive_schedule ps ON w.pm_id = ps.pm_id
      WHERE w.tenant_id = $1
    `;

        const params: any[] = [user.tenantId];
        let paramIdx = 2;

        // Filter by date range (uses due_date for calendar positioning)
        if (start) {
            query += ` AND w.due_date >= $${paramIdx}`;
            params.push(start);
            paramIdx++;
        }
        if (end) {
            query += ` AND w.due_date <= $${paramIdx}`;
            params.push(end);
            paramIdx++;
        }

        // Optional status filter
        if (status) {
            query += ` AND w.status = $${paramIdx}`;
            params.push(status);
            paramIdx++;
        }

        query += ` ORDER BY w.due_date ASC NULLS LAST, w.priority DESC`;

        const result = await db.query(query, params);

        // Map to calendar-friendly format
        const events = result.rows.map(row => ({
            id: row.id,
            title: row.title,
            start: row.start_time || row.due_date || row.requested_date,
            end: row.completion_time || row.due_date,
            description: row.description,
            type: row.type,
            priority: row.priority,
            status: row.status,
            asset: row.asset_name ? `${row.asset_name} (${row.tag_number})` : null,
            location: row.location_name,
            assignedTo: row.assigned_to,
            assignedToId: row.assigned_to_id,
            pm: row.pm_name ? {
                name: row.pm_name,
                scheduleType: row.schedule_type,
                interval: `${row.interval_value} ${row.interval_unit}`,
                nextDue: row.pm_next_due
            } : null,
            // Calendar color hint based on priority
            color: row.priority === 'Urgent' ? '#ef4444'
                : row.priority === 'High' ? '#f97316'
                    : row.priority === 'Medium' ? '#3b82f6'
                        : '#22c55e'
        }));

        return NextResponse.json({ data: events, count: events.length });
    } catch (error: any) {
        console.error('Calendar GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// PUT /api/calendar — Update a work order's schedule (drag-and-drop rescheduling)
// Body: { woId, dueDate, startTime?, assignedToId? }
export async function PUT(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const body = await req.json();
        const { woId, dueDate, startTime, assignedToId } = body;

        if (!woId || !dueDate) {
            return NextResponse.json({ error: 'Missing required fields: woId, dueDate' }, { status: 400 });
        }

        // Verify the work order belongs to this tenant
        const check = await db.query(
            'SELECT wo_id, status FROM maintenance.work_orders WHERE wo_id = $1 AND tenant_id = $2',
            [woId, user.tenantId]
        );
        if (check.rowCount === null || check.rowCount === 0) {
            return NextResponse.json({ error: 'Work order not found' }, { status: 404 });
        }

        // Build dynamic UPDATE
        const setClauses: string[] = ['due_date = $2'];
        const params: any[] = [woId, dueDate];
        let paramIdx = 3;

        if (startTime !== undefined) {
            setClauses.push(`start_time = $${paramIdx}`);
            params.push(startTime);
            paramIdx++;
        }

        if (assignedToId !== undefined) {
            setClauses.push(`assigned_to_id = $${paramIdx}`);
            params.push(assignedToId);
            paramIdx++;
        }

        const result = await db.query(
            `UPDATE maintenance.work_orders 
       SET ${setClauses.join(', ')}
       WHERE wo_id = $1 AND tenant_id = ${user.tenantId}
       RETURNING wo_id, title, due_date, start_time, assigned_to_id, status`,
            params
        );

        return NextResponse.json({
            message: 'Work order rescheduled',
            data: result.rows[0]
        });
    } catch (error: any) {
        console.error('Calendar PUT error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
