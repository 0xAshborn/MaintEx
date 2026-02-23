import { NextResponse } from 'next/server';

export async function GET() {
    return NextResponse.json({
        status: 'ok',
        message: 'CORTEX API (Next.js Edge) is running on Vercel',
        timestamp: new Date().toISOString()
    });
}
