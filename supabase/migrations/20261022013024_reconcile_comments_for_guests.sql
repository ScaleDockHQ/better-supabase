-- The guests migration was generated on a branch where comments still had
-- their own table, and comments_on_core moved them onto messaging first.
-- This puts back an empty table of that shape with its two policies, so the
-- guests migration applies. A later reconciling migration drops it again.
create table if not exists "better_supabase"."comments" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "author_id" uuid default auth.uid(),
  "body" text not null,
  "document" jsonb,
  "mentions" uuid[] not null default '{}',
  "parent_id" uuid references "better_supabase"."comments" ("id") on delete cascade,
  "created_at" timestamptz not null default clock_timestamp(),
  "edited_at" timestamptz,
  "deleted_at" timestamptz
);

alter table "better_supabase"."comments" enable row level security;

create policy "comments_insert" on "better_supabase"."comments"
  for insert to authenticated with check (false);

create policy "comments_read" on "better_supabase"."comments"
  for select to authenticated using (false);
