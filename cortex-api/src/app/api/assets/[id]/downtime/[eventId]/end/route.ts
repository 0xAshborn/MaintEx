import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// PUT /api/assets/[id]/downtime/[eventId]/end — End a downtime event
export async function PUT(req: NextRequest, { params }: { params: Promise<{ id: string; eventId: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id, eventId } = await params;

        const result = await db.query(
            `UPDATE assets.downtime_events
             SET ended_at = NOW()
             WHERE event_id = $1 AND asset_id = $2 AND tenant_id = $3 AND ended_at IS NULL
             RETURNING *`,
            [eventId, id, user.tenantId]
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'Active downtime event not found' }, { status: 404 });
        }

        // Check if there are any other active downtime events for this asset
        const activeCheck = await db.query(
            'SELECT 1 FROM assets.downtime_events WHERE asset_id = $1 AND tenant_id = $2 AND ended_at IS NULL',
            [id, user.tenantId]
        );

        // If no more active downtime, set asset status back to 'Operational'
        if (activeCheck.rowCount === null || activeCheck.rowCount === 0) {
            await db.query(
                "UPDATE assets.registry SET status = 'Operational' WHERE asset_id = $1 AND tenant_id = $2",
                [id, user.tenantId]
            );
        }

        return NextResponse.json({ message: 'Downtime ended', data: result.rows[0] });
    } catch (error: any) {
        console.error('End downtime error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
