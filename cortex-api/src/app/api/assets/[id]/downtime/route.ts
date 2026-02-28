import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// POST /api/assets/[id]/downtime — Record a new downtime event for an asset
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const body = await req.json();
        const { started_at, reason, failure_code, notes, wo_id } = body;

        if (!started_at || !reason) {
            return NextResponse.json({ error: 'Missing required fields: started_at, reason' }, { status: 400 });
        }

        // Verify asset belongs to this tenant
        const assetCheck = await db.query(
            'SELECT asset_id FROM assets.registry WHERE asset_id = $1 AND tenant_id = $2',
            [id, user.tenantId]
        );
        if (assetCheck.rowCount === null || assetCheck.rowCount === 0) {
            return NextResponse.json({ error: 'Asset not found' }, { status: 404 });
        }

        const result = await db.query(
            `INSERT INTO assets.downtime_events 
                (tenant_id, asset_id, started_at, reason, failure_code, notes, wo_id, created_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
             RETURNING *`,
            [user.tenantId, id, started_at, reason, failure_code || null, notes || null, wo_id || null, user.userId]
        );

        // Also set asset status to 'Down'
        await db.query(
            "UPDATE assets.registry SET status = 'Down' WHERE asset_id = $1 AND tenant_id = $2",
            [id, user.tenantId]
        );

        return NextResponse.json({ message: 'Downtime recorded', data: result.rows[0] }, { status: 201 });
    } catch (error: any) {
        console.error('Downtime POST error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// GET /api/assets/[id]/downtime — List downtime events for an asset
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const result = await db.query(
            `SELECT d.*, u.first_name || ' ' || u.last_name AS created_by_name
             FROM assets.downtime_events d
             LEFT JOIN core.users u ON d.created_by = u.user_id
             WHERE d.asset_id = $1 AND d.tenant_id = $2
             ORDER BY d.started_at DESC`,
            [id, user.tenantId]
        );

        return NextResponse.json({ data: result.rows, count: result.rowCount });
    } catch (error: any) {
        console.error('Downtime GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
