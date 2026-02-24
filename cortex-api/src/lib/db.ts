import { Pool } from 'pg';

// Only throw if we are actually trying to connect without a URL at runtime,
// not during the Vercel static build process.
const connectionString = process.env.DATABASE_URL;

export const db = new Pool({
    connectionString: connectionString,
    ssl: connectionString ? { rejectUnauthorized: false } : undefined
});

db.on('error', (err) => {
    console.error('Unexpected error on idle client', err);
});
