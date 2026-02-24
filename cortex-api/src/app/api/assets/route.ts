import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/assets — List all assets for the authenticated tenant
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT r.*, t.name AS type_name, l.name AS location_name
       FROM assets.registry r
       LEFT JOIN assets.types t ON r.asset_type_id = t.asset_type_id
       LEFT JOIN core.locations l ON r.location_id = l.location_id
       WHERE r.tenant_id = $1
       ORDER BY r.asset_id DESC`,
            [user.tenantId]
        );
        return NextResponse.json({ data: result.rows, count: result.rowCount });
    } catch (error: any) {
        console.error('Assets GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// POST /api/assets — Create a new asset for the authenticated tenant
export async function POST(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const body = await req.json();
        const { name, tagNumber, serialNumber, assetTypeId, locationId, status, criticality, manufacturer, model, installDate, purchaseCost, customFields } = body;

        if (!name || !tagNumber || !assetTypeId || !locationId) {
            return NextResponse.json({ error: 'Missing required fields: name, tagNumber, assetTypeId, locationId' }, { status: 400 });
        }

        const result = await db.query(
            `INSERT INTO assets.registry 
        (tenant_id, name, tag_number, serial_number, asset_type_id, location_id, status, criticality, manufacturer, model, install_date, purchase_cost, custom_fields)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
       RETURNING *`,
            [user.tenantId, name, tagNumber, serialNumber || null, assetTypeId, locationId, status || 'Operational', criticality || 'Medium', manufacturer || null, model || null, installDate || null, purchaseCost || 0, customFields ? JSON.stringify(customFields) : null]
        );

        return NextResponse.json({ message: 'Asset created', data: result.rows[0] }, { status: 201 });
    } catch (error: any) {
        if (error.code === '23505') {
            return NextResponse.json({ error: 'An asset with this tag number already exists for your tenant' }, { status: 409 });
        }
        console.error('Assets POST error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
