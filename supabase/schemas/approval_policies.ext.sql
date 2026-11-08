-- App-owned extension of better_supabase.approval_policies: columns the block reads and writes as fields.
-- better-supabase upgrade never rewrites this file.

alter table "better_supabase"."approval_policies"
  add column "description" text;
