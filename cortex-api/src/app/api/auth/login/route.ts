import { NextResponse } from 'next/server';
import { db } from '@/lib/db';
import bcrypt from 'bcryptjs';
import { signToken } from '@/lib/jwt';

export async function POST(req: Request) {
    try {
        const { email, password, subdomain, tenant_id } = await req.json();

        if (!email || !password) {
            return NextResponse.json({ error: 'Email and password are required' }, { status: 400 });
        }
        if (!subdomain && !tenant_id) {
            return NextResponse.json({ error: 'Either subdomain or tenant_id is required' }, { status: 400 });
        }

        // 1. Resolve tenant — by subdomain or by tenant_id
        let tenantId: number;
        if (subdomain) {
            const tenantRes = await db.query('SELECT tenant_id FROM core.tenants WHERE subdomain = $1', [subdomain]);
            if (tenantRes.rowCount === null || tenantRes.rowCount === 0) {
                return NextResponse.json({ error: 'Invalid subdomain' }, { status: 404 });
            }
            tenantId = tenantRes.rows[0].tenant_id;
        } else {
            const tenantRes = await db.query('SELECT tenant_id FROM core.tenants WHERE tenant_id = $1', [tenant_id]);
            if (tenantRes.rowCount === null || tenantRes.rowCount === 0) {
                return NextResponse.json({ error: 'Invalid tenant_id' }, { status: 404 });
            }
            tenantId = tenantRes.rows[0].tenant_id;
        }


        // 2. Fetch User strictly scoped to this tenant
        const userRes = await db.query('SELECT * FROM core.users WHERE email = $1 AND tenant_id = $2', [email, tenantId]);
        if (userRes.rowCount === null || userRes.rowCount === 0) {
            return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
        }

        const user = userRes.rows[0];

        // 3. Verify bcrypt password hash
        const isValid = bcrypt.compareSync(password, user.password_hash);
        if (!isValid) {
            return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
        }

        // 4. Generate JWT with context identifiers
        const token = signToken({
            userId: user.user_id,
            tenantId: user.tenant_id,
            roleId: user.role_id,
            email: user.email
        });

        return NextResponse.json({
            message: 'Login successful',
            token,
            user: {
                id: user.user_id,
                email: user.email,
                tenantId: user.tenant_id,
                roleId: user.role_id,
                name: `${user.first_name} ${user.last_name}`
            }
        });

    } catch (error: any) {
        console.error('Login error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
