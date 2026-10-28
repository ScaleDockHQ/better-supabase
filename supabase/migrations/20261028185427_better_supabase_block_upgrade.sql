-- better-supabase upgrade: steps that run before the schema diff.

-- knowledge: version 2 to 3. Knowledge collections with a visibility, a priority and grants to users or teams; documents join a collection, and system documents without a tenant are shared with every tenant.
alter table "better_supabase"."knowledge_documents" alter column "organization_id" drop not null;

-- memory: version 2 to 3. Memories gain a record scope, a category, a confidence, an expiry, soft deletes with restore and purge, and use counts. The path index covers the subject and skips deleted rows.
alter table "better_supabase"."memories"
  add column if not exists "subject_type" text,
  add column if not exists "subject_id" text,
  add column if not exists "category" text check ("category" ~ '^[a-z0-9][a-z0-9_-]*$'),
  add column if not exists "confidence" real check ("confidence" between 0 and 1),
  add column if not exists "expires_at" timestamptz,
  add column if not exists "deleted_at" timestamptz,
  add column if not exists "use_count" integer not null default 0,
  add column if not exists "last_used_at" timestamptz;
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = '"better_supabase"."memories"'::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = 'scope'
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."memories"', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."memories" add constraint "memories_scope_check" check ("scope" in ('user', 'agent', 'chat', 'project', 'organization', 'record'));
do $$
declare
  v_name text;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."memories"'::regclass and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%''organization''%IS NULL%'
      and pg_catalog.pg_get_constraintdef(c.oid) not like '%ANY%'
  loop
    execute format('alter table "better_supabase"."memories" drop constraint %I', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."memories" drop constraint if exists memories_owner_check;
alter table "better_supabase"."memories" add constraint memories_owner_check check (("scope" in ('organization', 'record')) = ("owner_id" is null));
alter table "better_supabase"."memories" drop constraint if exists memories_subject_check;
alter table "better_supabase"."memories" add constraint memories_subject_check check (("scope" = 'record') = ("subject_id" is not null) and ("subject_id" is null) = ("subject_type" is null));
do $$
declare
  v_index regclass;
begin
  select i.indexrelid::regclass into v_index
  from pg_catalog.pg_index i
  join pg_catalog.pg_class c on c.oid = i.indexrelid
  where i.indrelid = '"better_supabase"."memories"'::regclass and c.relname = 'memories_path_idx';
  if v_index is not null then
    execute format('drop index %s', v_index);
  end if;
end;
$$;

-- state-machine: version 2 to 3. status_history keeps the actor name, email, IP address and user agent that transition() takes as actor; history: "app" leaves the history to the app, and history.write: false only reads the app table.
alter table "better_supabase"."status_history" add column if not exists "actor_name" text;
alter table "better_supabase"."status_history" add column if not exists "actor_email" text;
alter table "better_supabase"."status_history" add column if not exists "ip_address" inet;
alter table "better_supabase"."status_history" add column if not exists "user_agent" text;
drop function if exists "better_supabase"."transition"(text, text, text, text);
