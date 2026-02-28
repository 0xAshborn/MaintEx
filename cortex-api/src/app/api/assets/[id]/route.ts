import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets/[id] — Get a single asset by ID
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const result = await db.query(
            `SELECT r.*, t.name AS type_name, l.name AS location_name
             FROM assets.registry r
             LEFT JOIN assets.types t ON r.asset_type_id = t.asset_type_id
             LEFT JOIN core.locations l ON r.location_id = l.location_id
             WHERE r.asset_id = $1 AND r.tenant_id = $2`,
            [id, user.tenantId]
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'Asset not found' }, { status: 404 });
        }

        return NextResponse.json({ data: result.rows[0] });
    } catch (error: any) {
        console.error('Asset GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// PUT /api/assets/[id] — Update an asset
export async function PUT(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const body = await req.json();

        // Build dynamic SET clause from provided fields
        const allowedFields: Record<string, string> = {
            name: 'name', tagNumber: 'tag_number', serialNumber: 'serial_number',
            assetTypeId: 'asset_type_id', locationId: 'location_id',
            status: 'status', criticality: 'criticality',
            manufacturer: 'manufacturer', model: 'model',
            installDate: 'install_date', purchaseCost: 'purchase_cost',
            customFields: 'custom_fields',
            // Also support snake_case from Postman
            tag_number: 'tag_number', serial_number: 'serial_number',
            asset_type_id: 'asset_type_id', location_id: 'location_id',
            install_date: 'install_date', purchase_cost: 'purchase_cost',
            custom_fields: 'custom_fields',
            last_meter_reading: 'last_meter_reading'
        };

        const setClauses: string[] = [];
        const values: any[] = [];
        let paramIdx = 1;

        for (const [key, col] of Object.entries(allowedFields)) {
            if (body[key] !== undefined) {
                setClauses.push(`${col} = $${paramIdx}`);
                values.push(key === 'customFields' || key === 'custom_fields' ? JSON.stringify(body[key]) : body[key]);
                paramIdx++;
            }
        }

        if (setClauses.length === 0) {
            return NextResponse.json({ error: 'No valid fields to update' }, { status: 400 });
        }

        values.push(id, user.tenantId);
        const result = await db.query(
            `UPDATE assets.registry SET ${setClauses.join(', ')}
             WHERE asset_id = $${paramIdx} AND tenant_id = $${paramIdx + 1}
             RETURNING *`,
            values
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'Asset not found' }, { status: 404 });
        }

        return NextResponse.json({ message: 'Asset updated', data: result.rows[0] });
    } catch (error: any) {
        if (error.code === '23505') {
            return NextResponse.json({ error: 'Duplicate tag number for this tenant' }, { status: 409 });
        }
        console.error('Asset PUT error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// DELETE /api/assets/[id] — Delete an asset
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { id } = await params;
        const result = await db.query(
            'DELETE FROM assets.registry WHERE asset_id = $1 AND tenant_id = $2 RETURNING asset_id',
            [id, user.tenantId]
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'Asset not found' }, { status: 404 });
        }

        return NextResponse.json({ message: 'Asset deleted' });
    } catch (error: any) {
        if (error.code === '23503') {
            return NextResponse.json({ error: 'Cannot delete asset — it has linked work orders or downtime events' }, { status: 409 });
        }
        console.error('Asset DELETE error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
