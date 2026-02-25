import { Pool } from 'pg';

const connectionString = process.env.DATABASE_URL;

export const db = new Pool({
    connectionString: connectionString,
    ssl: connectionString ? { rejectUnauthorized: false } : undefined,
    // For Supabase transaction pooler (pgBouncer), prepared statements must be disabled
    ...(connectionString?.includes('6543') ? { max: 10 } : {})
});

db.on('error', (err) => {
    console.error('Unexpected error on idle client', err);
});
