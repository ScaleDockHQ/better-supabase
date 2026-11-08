-- App-owned extension of better_supabase.meetings: columns the block reads and writes as fields.
-- better-supabase upgrade never rewrites this file.

alter table "better_supabase"."meetings"
  add column "room_code" text;
