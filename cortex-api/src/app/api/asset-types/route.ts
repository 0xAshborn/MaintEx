import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/asset-types — List all asset types for the authenticated tenant
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT * FROM assets.types WHERE tenant_id = $1 ORDER BY name`,
            [user.tenantId]
        );
        return NextResponse.json({ data: result.rows, count: result.rowCount });
    } catch (error: any) {
        console.error('Asset Types GET error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}

// POST /api/asset-types — Create a new asset type
export async function POST(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const { name, description } = await req.json();
        if (!name) return NextResponse.json({ error: 'Missing required field: name' }, { status: 400 });

        const result = await db.query(
            `INSERT INTO assets.types (tenant_id, name, description)
       VALUES ($1, $2, $3) RETURNING *`,
            [user.tenantId, name, description || null]
        );
        return NextResponse.json({ message: 'Asset type created', data: result.rows[0] }, { status: 201 });
    } catch (error: any) {
        if (error.code === '23505') {
            return NextResponse.json({ error: 'Asset type with this name already exists' }, { status: 409 });
        }
        console.error('Asset Types POST error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
