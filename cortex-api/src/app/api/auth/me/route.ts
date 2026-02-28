import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { authenticate } from '@/lib/auth';

// GET /api/auth/me — Get current user profile from JWT
export async function GET(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        const result = await db.query(
            `SELECT u.user_id, u.email, u.username, u.first_name, u.last_name,
                    u.is_active, u.last_login, u.created_at,
                    u.tenant_id, u.role_id,
                    r.role_name,
                    t.company_name, t.subdomain, t.plan
             FROM core.users u
             JOIN core.roles r ON u.role_id = r.role_id
             JOIN core.tenants t ON u.tenant_id = t.tenant_id
             WHERE u.user_id = $1 AND u.tenant_id = $2`,
            [user.userId, user.tenantId]
        );

        if (result.rowCount === null || result.rowCount === 0) {
            return NextResponse.json({ error: 'User not found' }, { status: 404 });
        }

        const row = result.rows[0];
        return NextResponse.json({
            data: {
                user: {
                    id: row.user_id,
                    email: row.email,
                    username: row.username,
                    firstName: row.first_name,
                    lastName: row.last_name,
                    isActive: row.is_active,
                    lastLogin: row.last_login,
                    createdAt: row.created_at
                },
                role: {
                    id: row.role_id,
                    name: row.role_name
                },
                tenant: {
                    id: row.tenant_id,
                    companyName: row.company_name,
                    subdomain: row.subdomain,
                    plan: row.plan
                }
            }
        });
    } catch (error: any) {
        console.error('Auth /me error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
