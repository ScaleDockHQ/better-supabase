-- better-supabase upgrade: steps that run before the schema diff.

-- inbox: version 7 to 8. Inbox contacts move onto the contacts block: each contact becomes a person (or joins the person it was linked to, or the active person with its email), contact_identities become person_identities, and conversations name the person. contacts, contact_identities and person_inbox_contacts are dropped.
-- The people and identity tables, so the contacts can move before the module files run.
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists "better_supabase"."companies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 300),
  "domain" text check ("domain" = lower("domain") and "domain" ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  "website" text,
  "vat_id" text,
  "lifecycle" text not null,
  "owner_user_id" uuid,
  "address" jsonb check ("address" is null or jsonb_typeof("address") = 'object'),
  "merged_into" uuid references "better_supabase"."companies" ("id"),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists companies_tenant_name_idx on "better_supabase"."companies" ("tenant_id", lower("name"), "id");
create unique index if not exists companies_domain_idx on "better_supabase"."companies" ("tenant_id", "domain")
  where "domain" is not null and "archived_at" is null;
create index if not exists companies_owner_idx on "better_supabase"."companies" ("owner_user_id");
create index if not exists companies_merged_into_idx on "better_supabase"."companies" ("merged_into");
alter table "better_supabase"."companies" enable row level security;
revoke all on "better_supabase"."companies" from public, anon, authenticated;
grant select on "better_supabase"."companies" to authenticated;
grant all on "better_supabase"."companies" to service_role;
drop policy if exists companies_read on "better_supabase"."companies";
create policy companies_read on "better_supabase"."companies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table if not exists "better_supabase"."people" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 300),
  "email" text check ("email" = lower("email") and "email" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "phone" text,
  "title" text,
  "lifecycle" text not null,
  "owner_user_id" uuid,
  "user_id" uuid,
  "avatar_url" text,
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "merged_into" uuid references "better_supabase"."people" ("id"),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists people_tenant_name_idx on "better_supabase"."people" ("tenant_id", lower("name"), "id");
create unique index if not exists people_email_idx on "better_supabase"."people" ("tenant_id", "email")
  where "email" is not null and "archived_at" is null;
create index if not exists people_owner_idx on "better_supabase"."people" ("owner_user_id");
create index if not exists people_user_idx on "better_supabase"."people" ("user_id");
create index if not exists people_merged_into_idx on "better_supabase"."people" ("merged_into");
alter table "better_supabase"."people" enable row level security;
revoke all on "better_supabase"."people" from public, anon, authenticated;
grant select on "better_supabase"."people" to authenticated;
grant all on "better_supabase"."people" to service_role;
drop policy if exists people_read on "better_supabase"."people";
create policy people_read on "better_supabase"."people"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table if not exists "better_supabase"."company_people" (
  "tenant_id" uuid not null,
  "company_id" uuid not null references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid not null references "better_supabase"."people" ("id") on delete cascade,
  "role" text,
  "is_primary" boolean not null default false,
  "created_at" timestamptz not null default now(),
  primary key ("company_id", "person_id")
);
create index if not exists company_people_person_idx on "better_supabase"."company_people" ("person_id");
create unique index if not exists company_people_primary_idx on "better_supabase"."company_people" ("company_id") where "is_primary";
alter table "better_supabase"."company_people" enable row level security;
revoke all on "better_supabase"."company_people" from public, anon, authenticated;
grant select on "better_supabase"."company_people" to authenticated;
grant all on "better_supabase"."company_people" to service_role;
drop policy if exists company_people_read on "better_supabase"."company_people";
create policy company_people_read on "better_supabase"."company_people"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

alter table "better_supabase"."people" add column if not exists "avatar_url" text;
alter table "better_supabase"."people" add column if not exists "metadata" jsonb not null default '{}'::jsonb;

create table if not exists "better_supabase"."person_identities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "person_id" uuid not null references "better_supabase"."people" ("id") on delete cascade,
  "channel" text not null check (length("channel") between 1 and 50),
  "address" text not null check (length("address") between 1 and 500),
  "verified_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "channel", "address")
);
create index if not exists person_identities_person_idx on "better_supabase"."person_identities" ("person_id");
alter table "better_supabase"."person_identities" enable row level security;
revoke all on "better_supabase"."person_identities" from public, anon, authenticated;
grant select on "better_supabase"."person_identities" to authenticated;
grant all on "better_supabase"."person_identities" to service_role;
drop policy if exists person_identities_read on "better_supabase"."person_identities";
create policy person_identities_read on "better_supabase"."person_identities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));


do $$
declare
  r record;
  j jsonb;
  v_contact uuid;
  v_tenant uuid;
  v_person uuid;
  v_email text;
  v_key record;
begin
  if to_regclass('"better_supabase".contacts') is null then
    return;
  end if;
  -- The foreign keys on the old contacts go first: conversations and identity
  -- links may move to a person whose id no contact has.
  for v_key in
    select c.conname, c.conrelid::regclass as tbl from pg_constraint c
    where c.contype = 'f' and c.confrelid = '"better_supabase".contacts'::regclass
      and c.conrelid <> '"better_supabase".contacts'::regclass
  loop
    execute format('alter table %s drop constraint %I', v_key.tbl, v_key.conname);
  end loop;
  for r in select c.id, to_jsonb(c) as j from "better_supabase".contacts c order by c.id loop
    j := r.j;
    v_contact := r.id;
    v_tenant := (j ->> 'tenant_id')::uuid;
    v_person := null;
    v_email := lower(btrim(j ->> 'email'));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
      v_email := null;
    end if;
    if to_regclass('"better_supabase".person_inbox_contacts') is not null then
      select l.person_id into v_person from "better_supabase".person_inbox_contacts l where l.contact_id = v_contact;
    end if;
    if v_person is null and v_email is not null then
      select coalesce(p."merged_into", p."id") into v_person from "better_supabase"."people" p
      where p."tenant_id" = v_tenant and p."email" = v_email and p."archived_at" is null
      order by p."created_at", p."id" limit 1;
    end if;
    if v_person is null then
      insert into "better_supabase"."people" ("id", "tenant_id", "name", "email", "phone", "lifecycle", "user_id", "avatar_url", "metadata", "created_at")
      values (v_contact, v_tenant, left(coalesce(nullif(j ->> 'name', ''), nullif(btrim(j ->> 'email'), ''), nullif(j ->> 'phone', ''), 'Unknown contact'), 300), v_email, nullif(j ->> 'phone', ''), 'lead', (j ->> 'user_id')::uuid, j ->> 'avatar_url', coalesce(j -> 'metadata', '{}'::jsonb) || case when v_email is null and nullif(j ->> 'email', '') is not null then jsonb_build_object('email', j ->> 'email') else '{}'::jsonb end, coalesce((j ->> 'created_at')::timestamptz, now()))
      on conflict do nothing
      returning "id" into v_person;
    end if;
    if v_person is null then
      raise exception 'inbox: contact % could not become a person', v_contact
        using hint = 'a person with this id or email exists in another state; resolve it, then run better-supabase upgrade again';
    end if;
    if v_person <> v_contact then
      update "better_supabase"."people" p set
        "user_id" = coalesce(p."user_id", (j ->> 'user_id')::uuid),
        "phone" = coalesce(p."phone", nullif(j ->> 'phone', '')),
        "avatar_url" = coalesce(p."avatar_url", j ->> 'avatar_url')
      where p."id" = v_person;
      update "better_supabase"."inbox_conversations" v set "contact_id" = v_person where v."contact_id" = v_contact;
    end if;
    if to_regclass('"better_supabase".contact_identities') is not null then
      insert into "better_supabase"."person_identities" ("tenant_id", "person_id", "channel", "address", "created_at")
      select i.tenant_id, v_person, i.channel, i.external_id, coalesce((to_jsonb(i) ->> 'created_at')::timestamptz, now())
      from "better_supabase".contact_identities i where i.contact_id = v_contact
      on conflict do nothing;
    end if;
  end loop;
  drop table if exists "better_supabase".person_inbox_contacts cascade;
  drop table if exists "better_supabase".contact_identities cascade;
  drop table "better_supabase".contacts cascade;
end;
$$;
drop function if exists "better_supabase"."inbox_resolve_contact"(uuid, jsonb);
drop function if exists "better_supabase"."link_inbox_contact"(uuid, uuid);
drop function if exists "better_supabase"."unlink_inbox_contact"(uuid);
drop function if exists "better_supabase"."person_for_inbox_contact"(uuid, boolean);
