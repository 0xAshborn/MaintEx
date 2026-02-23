import { NextResponse } from 'next/server';
import { db } from '@/lib/db';
import bcrypt from 'bcryptjs';
import { signToken } from '@/lib/jwt';

export async function POST(req: Request) {
    try {
        const body = await req.json();
        const { companyName, subdomain, firstName, lastName, email, password } = body;

        // 1. Basic validation
        if (!companyName || !subdomain || !email || !password || !firstName || !lastName) {
            return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
        }

        // 2. Check if subdomain already exists
        const subCheck = await db.query('SELECT 1 FROM core.tenants WHERE subdomain = $1', [subdomain]);
        if (subCheck.rowCount !== null && subCheck.rowCount > 0) {
            return NextResponse.json({ error: 'Subdomain already taken' }, { status: 409 });
        }

        // 3. Check if email already exists globally (simplified for MVP)
        const emailCheck = await db.query('SELECT 1 FROM core.users WHERE email = $1', [email]);
        if (emailCheck.rowCount !== null && emailCheck.rowCount > 0) {
            return NextResponse.json({ error: 'Email already registered' }, { status: 409 });
        }

        // 4. Provision tenant via existing Postgres function
        const provisionRes = await db.query('SELECT core.provision_tenant($1, $2, $3) AS new_tenant_id', [companyName, subdomain, 'Starter']);
        const tenantId = provisionRes.rows[0].new_tenant_id;

        // 5. Get default "Admin" role for this new tenant
        const roleRes = await db.query("SELECT role_id FROM core.roles WHERE tenant_id = $1 AND role_name = 'Admin'", [tenantId]);
        const roleId = roleRes.rows[0].role_id;

        // 6. Hash password using bcryptjs
        const passwordHash = bcrypt.hashSync(password, 10);

        // 7. Insert the new User
        const userRes = await db.query(
            `INSERT INTO core.users (tenant_id, username, email, password_hash, first_name, last_name, role_id) 
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING user_id`,
            [tenantId, email, email, passwordHash, firstName, lastName, roleId] // Re-use email as username
        );
        const userId = userRes.rows[0].user_id;

        // 8. Generate standard JWT
        const token = signToken({ userId, tenantId, roleId, email });

        return NextResponse.json({
            message: 'Registration successful',
            token,
            user: { id: userId, email, tenantId, roleId, firstName, lastName }
        }, { status: 201 });

    } catch (error: any) {
        console.error('Registration error:', error);
        return NextResponse.json({ error: 'Internal Server Error', details: error.message }, { status: 500 });
    }
}
