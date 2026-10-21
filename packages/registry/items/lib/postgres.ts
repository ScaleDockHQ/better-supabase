import { createPostgres } from "better-supabase/postgres";

/**
 * One pool for the server-side blocks. It reads `SUPABASE_DB_URL`, then
 * `DATABASE_URL`. `postgres.admin` bypasses RLS: use it only in route handlers
 * that check their own secret, never with a user's input.
 */
export const postgres = createPostgres();
