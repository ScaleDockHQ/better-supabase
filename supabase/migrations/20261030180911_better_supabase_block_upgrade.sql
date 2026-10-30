-- better-supabase upgrade: steps that run before the schema diff.

-- sequences: version 1 to 2. Sequence runs live on enrollments: each sequence_enrollments row moves onto its enrollment in the program sequence:<id>, its next step becomes the open step row, and sequence_enrollments is dropped.
create table if not exists "better_supabase"."enrollment_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- The subject types it enrolls; empty enrolls any.
  "subject_types" text[] not null default '{}',
  -- [{ id, title, description }], in order.
  "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists "better_supabase"."enrollments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "program" text not null check (length("program") between 1 and 200),
  "program_version" integer,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  "steps" text[] not null default '{}',
  "completed_steps" integer not null default 0 check ("completed_steps" >= 0),
  "status" text not null default 'active' check ("status" in ('active', 'completed', 'cancelled')),
  "enrolled_by" uuid,
  "enrolled_at" timestamptz not null default now(),
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "paused_at" timestamptz,
  "cancel_reason" text check ("cancel_reason" is null or length("cancel_reason") between 1 and 200),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" = 'user') = ("user_id" is not null)),
  check ("user_id" is null or "subject_id" = "user_id"::text),
  unique nulls not distinct ("tenant_id", "program", "subject_type", "subject_id")
);
create index if not exists "enrollments_program_idx" on "better_supabase"."enrollments" ("tenant_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "better_supabase"."enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "better_supabase"."enrollments" ("user_id");

-- A completed step, or an open one whose program step has an assignee or a
-- due date (completed_at is null until it is done).
create table if not exists "better_supabase"."enrollment_steps" (
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid,
  "step" text not null,
  "assignee_role" text check ("assignee_role" is null or "assignee_role" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "assignee_user_id" uuid references auth.users (id) on delete set null,
  "due_at" timestamptz,
  "completed_by" uuid,
  "completed_at" timestamptz default now(),
  primary key ("enrollment_id", "step")
);
create index if not exists "enrollment_steps_assignee_idx" on "better_supabase"."enrollment_steps" ("assignee_user_id", "due_at");
create index if not exists "enrollment_steps_due_idx" on "better_supabase"."enrollment_steps" ("tenant_id", "due_at") where "completed_at" is null;

alter table "better_supabase"."enrollment_programs" enable row level security;
revoke all on "better_supabase"."enrollment_programs" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_programs" to authenticated;
grant all on "better_supabase"."enrollment_programs" to service_role;
drop policy if exists "enrollment_programs_read" on "better_supabase"."enrollment_programs";
create policy enrollment_programs_read on "better_supabase"."enrollment_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollments" enable row level security;
revoke all on "better_supabase"."enrollments" from public, anon, authenticated;
grant select on "better_supabase"."enrollments" to authenticated;
grant all on "better_supabase"."enrollments" to service_role;
drop policy if exists "enrollments_read" on "better_supabase"."enrollments";
create policy enrollments_read on "better_supabase"."enrollments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollment_steps" enable row level security;
revoke all on "better_supabase"."enrollment_steps" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_steps" to authenticated;
grant all on "better_supabase"."enrollment_steps" to service_role;
drop policy if exists "enrollment_steps_read" on "better_supabase"."enrollment_steps";
create policy enrollment_steps_read on "better_supabase"."enrollment_steps"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"));

alter table "better_supabase"."enrollments" add column if not exists "paused_at" timestamptz;
alter table "better_supabase"."enrollments" add column if not exists "cancel_reason" text check ("cancel_reason" is null or length("cancel_reason") between 1 and 200);
-- A recipient's run is their enrollment in the program sequence:<id>: these
-- columns say who it goes to and how sending went, and the open step row is
-- the step that runs next, due when it runs.
alter table "better_supabase"."enrollments" add column if not exists "sequence_id" uuid references "better_supabase"."sequences" ("id") on delete cascade;
alter table "better_supabase"."enrollments" add column if not exists "sequence_address" text check ("sequence_address" is null or (length("sequence_address") <= 320 and "sequence_address" ~ '^[^@[:space:]]+@[^@[:space:]]+$'));
alter table "better_supabase"."enrollments" add column if not exists "sequence_name" text check ("sequence_name" is null or length("sequence_name") <= 200);
alter table "better_supabase"."enrollments" add column if not exists "sequence_mail_account_id" uuid references "better_supabase"."mail_accounts" ("id") on delete set null;
alter table "better_supabase"."enrollments" add column if not exists "sequence_mail_thread_id" uuid references "better_supabase"."mail_threads" ("id") on delete set null;
alter table "better_supabase"."enrollments" add column if not exists "sequence_attempts" integer not null default 0 check ("sequence_attempts" >= 0);
alter table "better_supabase"."enrollments" add column if not exists "sequence_last_error" text check ("sequence_last_error" is null or length("sequence_last_error") <= 2000);
alter table "better_supabase"."enrollments" add column if not exists "sequence_variables" jsonb not null default '{}' check (jsonb_typeof("sequence_variables") = 'object');
create index if not exists "enrollments_sequence_idx" on "better_supabase"."enrollments" ("sequence_id", "status") where "sequence_id" is not null;
create index if not exists "enrollments_sequence_address_idx" on "better_supabase"."enrollments" ("tenant_id", lower("sequence_address")) where "sequence_id" is not null and "status" = 'active';
create index if not exists "enrollments_sequence_account_idx" on "better_supabase"."enrollments" ("sequence_mail_account_id") where "sequence_mail_account_id" is not null;
create index if not exists "enrollments_sequence_thread_idx" on "better_supabase"."enrollments" ("sequence_mail_thread_id") where "sequence_mail_thread_id" is not null;
create index if not exists "enrollment_steps_open_due_idx" on "better_supabase"."enrollment_steps" ("due_at") where "completed_at" is null;
do $upgrade$
begin
  if to_regclass('better_supabase.sequence_enrollments') is null then
    return;
  end if;
  update "better_supabase"."enrollments" x
  set "sequence_id" = m.sequence_id, "sequence_address" = m.address, "sequence_name" = m.name,
    "sequence_mail_account_id" = m.mail_account_id, "sequence_mail_thread_id" = m.mail_thread_id, "sequence_attempts" = m.attempts,
    "sequence_last_error" = (to_jsonb(m) ->> 'last_error'), "sequence_variables" = m.variables,
    "paused_at" = case when m.status::text = 'paused' and x."status" = 'active' then m.updated_at end,
    "cancel_reason" = case when x."status" = 'cancelled' then m.exit_reason::text end
  from "better_supabase".sequence_enrollments m
  where x."id" = m.enrollment_id;
  insert into "better_supabase"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "due_at", "completed_by", "completed_at")
  select m.enrollment_id, m.tenant_id, m.step, m.next_run_at, null, null
  from "better_supabase".sequence_enrollments m
  join "better_supabase"."enrollments" x on x."id" = m.enrollment_id
  where m.step is not null and m.status::text in ('active', 'paused') and x."status" = 'active'
  on conflict do nothing;
  drop table "better_supabase".sequence_enrollments;
end;
$upgrade$;
