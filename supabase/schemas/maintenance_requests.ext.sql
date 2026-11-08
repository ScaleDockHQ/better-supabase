-- App-owned extension of better_supabase.maintenance_requests: columns the block reads and writes as fields.
-- better-supabase upgrade never rewrites this file.

alter table "better_supabase"."maintenance_requests"
  add column "unit_id" uuid,
  add column "lease_id" uuid;
