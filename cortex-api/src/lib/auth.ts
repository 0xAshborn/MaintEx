import { NextRequest } from 'next/server';
import { verifyToken } from './jwt';

export interface AuthUser {
    userId: number;
    tenantId: number;
    roleId: number;
    email: string;
}

/**
 * Extracts and verifies the JWT from the Authorization header.
 * Returns the decoded user payload or null if invalid/missing.
 */
export function authenticate(req: NextRequest): AuthUser | null {
    const authHeader = req.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) return null;

    const token = authHeader.substring(7);
    const decoded = verifyToken(token);
    if (!decoded || typeof decoded === 'string') return null;

    return decoded as AuthUser;
}
