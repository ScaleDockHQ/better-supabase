-- better-supabase sql upgrade: steps that run before the schema diff.

-- onboarding: version 1 to 2. Onboarding checklists run on enrollments: each checklist and subject becomes an enrollment in the program onboarding:<checklist> with its completed steps, and onboarding_progress is dropped.
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
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" = 'user') = ("user_id" is not null)),
  check ("user_id" is null or "subject_id" = "user_id"::text),
  unique nulls not distinct ("tenant_id", "program", "subject_type", "subject_id")
);
create index if not exists "enrollments_program_idx" on "better_supabase"."enrollments" ("tenant_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "better_supabase"."enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "better_supabase"."enrollments" ("user_id");

create table if not exists "better_supabase"."enrollment_steps" (
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid,
  "step" text not null,
  "completed_by" uuid,
  "completed_at" timestamptz not null default now(),
  primary key ("enrollment_id", "step")
);

alter table "better_supabase"."enrollment_programs" enable row level security;
revoke all on "better_supabase"."enrollment_programs" from anon, authenticated;
grant select on "better_supabase"."enrollment_programs" to authenticated;
grant all on "better_supabase"."enrollment_programs" to service_role;
drop policy if exists "enrollment_programs_read" on "better_supabase"."enrollment_programs";
create policy "enrollment_programs_read" on "better_supabase"."enrollment_programs" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollments" enable row level security;
revoke all on "better_supabase"."enrollments" from anon, authenticated;
grant select on "better_supabase"."enrollments" to authenticated;
grant all on "better_supabase"."enrollments" to service_role;
drop policy if exists "enrollments_read" on "better_supabase"."enrollments";
create policy "enrollments_read" on "better_supabase"."enrollments" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollment_steps" enable row level security;
revoke all on "better_supabase"."enrollment_steps" from anon, authenticated;
grant select on "better_supabase"."enrollment_steps" to authenticated;
grant all on "better_supabase"."enrollment_steps" to service_role;
drop policy if exists "enrollment_steps_read" on "better_supabase"."enrollment_steps";
create policy "enrollment_steps_read" on "better_supabase"."enrollment_steps" for select to authenticated
  using (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"));

do $upgrade$
begin
  if to_regclass('better_supabase.onboarding_progress') is null then
    return;
  end if;
  insert into "better_supabase"."enrollments" ("tenant_id", "program", "subject_type", "subject_id", "user_id", "steps", "enrolled_at")
  select x.organization_id, 'onboarding:' || x.checklist, case when x.organization_id is null then 'user' else 'organization' end, coalesce(x.organization_id::text, x.user_id::text), x.user_id,
    coalesce(c.steps, array_agg(distinct x.step order by x.step)), min(x.completed_at)
  from "better_supabase".onboarding_progress x
  left join (values ('getting-started', 'organization', array['customer', 'invite', 'api-key', 'plan']::text[])) as c(checklist, scope, steps) on c.checklist = x.checklist
  group by x.organization_id, x.user_id, x.checklist, c.steps
  on conflict do nothing;
  insert into "better_supabase"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "completed_by", "completed_at")
  select y."id", x.organization_id, x.step, x.completed_by, x.completed_at
  from "better_supabase".onboarding_progress x
  join "better_supabase"."enrollments" y on y."tenant_id" is not distinct from x.organization_id
    and y."program" = 'onboarding:' || x.checklist
    and y."subject_type" = case when x.organization_id is null then 'user' else 'organization' end
    and y."subject_id" = coalesce(x.organization_id::text, x.user_id::text)
  on conflict do nothing;
  update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then (select max(y."completed_at") from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id") end
  where x."program" like 'onboarding:%';
  drop table "better_supabase".onboarding_progress;
end;
$upgrade$;
