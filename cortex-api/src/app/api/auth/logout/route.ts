import { NextRequest, NextResponse } from 'next/server';
import { authenticate } from '@/lib/auth';

// POST /api/auth/logout — Invalidate the current session
// Note: With stateless JWTs, true server-side invalidation requires a token blacklist.
// For the MVP, this endpoint acknowledges the logout and the client discards the token.
export async function POST(req: NextRequest) {
    const user = authenticate(req);
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

    // In a stateless JWT system, the client is responsible for discarding the token.
    // A production system would add the token's JTI to a Redis blacklist here.
    return NextResponse.json({
        message: 'Logged out successfully'
    });
}
