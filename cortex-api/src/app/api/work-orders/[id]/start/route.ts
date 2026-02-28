import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// POST /api/work-orders/[id]/start — Transition WO to "In Progress"
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;

        // Verify the WO exists and is in a valid state to start
        const check = await db.query(
            'SELECT wo_id, status FROM maintenance.work_orders WHERE wo_id = $1 AND tenant_id = $2',
            [id, user.tenantId]
        );
        if (check.rowCount === null || check.rowCount === 0) {
            return NextResponse.json({ error: 'Work order not found' }, { status: 404 });
        }

        const currentStatus = check.rows[0].status;
        if (currentStatus === 'Complete') {
            return NextResponse.json({ error: 'Cannot start a completed work order' }, { status: 409 });
        }
        if (currentStatus === 'In Progress') {
            return NextResponse.json({ error: 'Work order is already in progress' }, { status: 409 });
        }

        const result = await db.query(
            `UPDATE maintenance.work_orders
             SET status = 'In Progress', start_time = NOW()
             WHERE wo_id = $1 AND tenant_id = $2
             RETURNING wo_id, title, status, start_time`,
            [id, user.tenantId]
        );

        return NextResponse.json({ message: 'Work order started', data: result.rows[0] });
    } catch (error: any) {
        console.error('WO start error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
