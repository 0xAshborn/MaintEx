import { NextRequest, NextResponse } from 'next/server';
import { authenticate } from '@/lib/auth';
import { signToken } from '@/lib/jwt';

// POST /api/auth/refresh — Issue a fresh JWT using the current valid token
export async function POST(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    try {
        // Issue a new token with the same payload but a fresh expiry
        const newToken = signToken({
            userId: user.userId,
            tenantId: user.tenantId,
            roleId: user.roleId,
            email: user.email
        });

        return NextResponse.json({
            data: {
                token: newToken,
                expiresIn: '7d'
            }
        });
    } catch (error: any) {
        console.error('Auth /refresh error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
