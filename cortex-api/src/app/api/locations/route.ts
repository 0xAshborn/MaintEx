import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/locations — List all locations for the authenticated tenant
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT * FROM core.locations WHERE tenant_id = $1 ORDER BY name`,
            [user.tenantId]
        );
        return NextResponse.json({ data: result.rows, count: result.rowCount });
    } catch (error: any) {
        console.error('Locations GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// POST /api/locations — Create a new location
export async function POST(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { name, address, parentLocationId, latitude, longitude } = await req.json();
        if (!name) return NextResponse.json({ error: 'Missing required field: name' }, { status: 400 });

        const result = await db.query(
            `INSERT INTO core.locations (tenant_id, name, address, parent_location_id, latitude, longitude)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
            [user.tenantId, name, address || null, parentLocationId || null, latitude || null, longitude || null]
        );
        return NextResponse.json({ message: 'Location created', data: result.rows[0] }, { status: 201 });
    } catch (error: any) {
        console.error('Locations POST error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
