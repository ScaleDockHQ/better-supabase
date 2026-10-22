-- Built concurrently, outside the block extensions migration's transaction,
-- so writes to bookings continue while it builds (doctor BS229).
CREATE INDEX CONCURRENTLY IF NOT EXISTS bookings_series_idx ON better_supabase.bookings USING btree (series_id, during);
