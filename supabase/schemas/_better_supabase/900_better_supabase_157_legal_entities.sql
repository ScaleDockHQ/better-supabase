-- better-supabase module: legal-entities
-- @bsb-block legal-entities@1 managed
-- @bsb-hash sha256:fcb24b1ebdeff7ed383890637dd9a9f8ebab82fb848cd395c71652cda394f870
-- Several legal entities inside one organization, each with its VAT and chamber numbers, bank account, logo and fiscal settings and one default per organization. Settings resolve from the legal entity to the organization to the code default, and options.on adds a nullable legal_entity_id to invoices, quotes, orders, numbering, accounting, inventory locations and settings; null means the default entity.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."legal_entities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."legal_entities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."legal_entities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."legal_entities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."legal_entities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."legal_entity_settings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."legal_entity_settings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."legal_entity_settings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."legal_entity_settings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."legal_entity_settings";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Legal entities inside one organization (ADR 0142): their details, the
-- default entity, per-entity settings, and the optional legal_entity_id
-- column on the tables blocks.legal-entities.options.on names.

-- The legal entities of an organization: the companies that issue documents,
-- keep books and pay tax. Contacts, products and members stay shared.
create table if not exists "better_supabase"."legal_entities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null check ("code" ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,31}$'),
  "name" text not null check (length("name") between 1 and 200),
  "address" jsonb not null default '{}'::jsonb check (jsonb_typeof("address") = 'object'),
  "vat_number" text check ("vat_number" is null or length("vat_number") between 1 and 50),
  "coc_number" text check ("coc_number" is null or length("coc_number") between 1 and 50),
  "iban" text check ("iban" is null or length("iban") between 1 and 34),
  "bic" text check ("bic" is null or length("bic") between 1 and 11),
  "logo_attachment_id" uuid references "better_supabase"."attachments" ("id") on delete set null,
  "default_currency" text check ("default_currency" is null or "default_currency" ~ '^[A-Z]{3}$'),
  -- { "fiscalYearStartMonth": 1 to 12, "taxPeriod": "monthly" or "quarterly" }.
  "fiscal" jsonb not null default '{"fiscalYearStartMonth": 1, "taxPeriod": "quarterly"}'::jsonb check (jsonb_typeof("fiscal") = 'object'),
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  unique ("tenant_id", "id"),
  check (not ("is_default" and "archived_at" is not null))
);
-- One default entity per organization.
create unique index if not exists "legal_entities_default_idx" on "better_supabase"."legal_entities" ("tenant_id") where "is_default";
create index if not exists "legal_entities_logo_idx" on "better_supabase"."legal_entities" ("logo_attachment_id") where "logo_attachment_id" is not null;
alter table "better_supabase"."legal_entities" enable row level security;
revoke all on "better_supabase"."legal_entities" from public, anon, authenticated;
grant select on "better_supabase"."legal_entities" to authenticated;
grant all on "better_supabase"."legal_entities" to service_role;
drop policy if exists legal_entities_read on "better_supabase"."legal_entities";
create policy legal_entities_read on "better_supabase"."legal_entities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('legal_entities.read')));

-- Settings that differ per legal entity; resolve_setting falls back to the
-- organization's setting, then to the code default.
create table if not exists "better_supabase"."legal_entity_settings" (
  "tenant_id" uuid not null,
  "legal_entity_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  "value" jsonb not null,
  "updated_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "updated_at" timestamptz not null default now(),
  primary key ("legal_entity_id", "key"),
  foreign key ("tenant_id", "legal_entity_id") references "better_supabase"."legal_entities" ("tenant_id", "id") on delete cascade
);
create index if not exists "legal_entity_settings_tenant_idx" on "better_supabase"."legal_entity_settings" ("tenant_id", "legal_entity_id");
create index if not exists "legal_entity_settings_updated_by_idx" on "better_supabase"."legal_entity_settings" ("updated_by") where "updated_by" is not null;
alter table "better_supabase"."legal_entity_settings" enable row level security;
revoke all on "better_supabase"."legal_entity_settings" from public, anon, authenticated;
grant select on "better_supabase"."legal_entity_settings" to authenticated;
grant all on "better_supabase"."legal_entity_settings" to service_role;
drop policy if exists legal_entity_settings_read on "better_supabase"."legal_entity_settings";
create policy legal_entity_settings_read on "better_supabase"."legal_entity_settings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('legal_entities.read')));
alter table "better_supabase"."invoices" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."invoices" drop constraint if exists "bsb_invoices_legal_entity_fk";
alter table "better_supabase"."invoices" add constraint "bsb_invoices_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_invoices_legal_entity_idx" on "better_supabase"."invoices" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
do $$
declare
  v_key record;
begin
  for v_key in
    select i.indexrelid, c.conname, ic.relname as index_name,
      (select string_agg(quote_ident(a.attname), ', ' order by k.ord)
       from unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
       join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum) as cols
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    left join pg_constraint c on c.conindid = i.indexrelid and c.contype = 'u'
    where i.indrelid = '"better_supabase"."invoices"'::regclass and i.indisunique and not i.indisprimary
      and i.indpred is null and i.indexprs is null
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        @> array['tenant_id']
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        && array['number', 'identifier']
      and not (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        @> array['legal_entity_id']
  loop
    if v_key.conname is not null then
      execute format('alter table "better_supabase"."invoices" drop constraint %I', v_key.conname);
    else
      execute format('drop index %s', v_key.indexrelid::regclass);
    end if;
    execute format('create unique index %I on "better_supabase"."invoices" (%s, coalesce(legal_entity_id, ''00000000-0000-0000-0000-000000000000''::uuid))',
      v_key.index_name, v_key.cols);
  end loop;
end $$;
alter table "better_supabase"."quotes" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."quotes" drop constraint if exists "bsb_quotes_legal_entity_fk";
alter table "better_supabase"."quotes" add constraint "bsb_quotes_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_quotes_legal_entity_idx" on "better_supabase"."quotes" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
do $$
declare
  v_key record;
begin
  for v_key in
    select i.indexrelid, c.conname, ic.relname as index_name,
      (select string_agg(quote_ident(a.attname), ', ' order by k.ord)
       from unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
       join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum) as cols
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    left join pg_constraint c on c.conindid = i.indexrelid and c.contype = 'u'
    where i.indrelid = '"better_supabase"."quotes"'::regclass and i.indisunique and not i.indisprimary
      and i.indpred is null and i.indexprs is null
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        @> array['tenant_id']
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        && array['number']
      and not (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        @> array['legal_entity_id']
  loop
    if v_key.conname is not null then
      execute format('alter table "better_supabase"."quotes" drop constraint %I', v_key.conname);
    else
      execute format('drop index %s', v_key.indexrelid::regclass);
    end if;
    execute format('create unique index %I on "better_supabase"."quotes" (%s, coalesce(legal_entity_id, ''00000000-0000-0000-0000-000000000000''::uuid))',
      v_key.index_name, v_key.cols);
  end loop;
end $$;
alter table "better_supabase"."orders" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."orders" drop constraint if exists "bsb_orders_legal_entity_fk";
alter table "better_supabase"."orders" add constraint "bsb_orders_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_orders_legal_entity_idx" on "better_supabase"."orders" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
do $$
declare
  v_key record;
begin
  for v_key in
    select i.indexrelid, c.conname, ic.relname as index_name,
      (select string_agg(quote_ident(a.attname), ', ' order by k.ord)
       from unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
       join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum) as cols
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    left join pg_constraint c on c.conindid = i.indexrelid and c.contype = 'u'
    where i.indrelid = '"better_supabase"."orders"'::regclass and i.indisunique and not i.indisprimary
      and i.indpred is null and i.indexprs is null
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        @> array['tenant_id']
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        && array['number', 'invoice_number']
      and not (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        @> array['legal_entity_id']
  loop
    if v_key.conname is not null then
      execute format('alter table "better_supabase"."orders" drop constraint %I', v_key.conname);
    else
      execute format('drop index %s', v_key.indexrelid::regclass);
    end if;
    execute format('create unique index %I on "better_supabase"."orders" (%s, coalesce(legal_entity_id, ''00000000-0000-0000-0000-000000000000''::uuid))',
      v_key.index_name, v_key.cols);
  end loop;
end $$;
alter table "better_supabase"."number_sequences" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."number_sequences" drop constraint if exists "bsb_number_sequences_legal_entity_fk";
alter table "better_supabase"."number_sequences" add constraint "bsb_number_sequences_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_number_sequences_legal_entity_idx" on "better_supabase"."number_sequences" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
alter table "better_supabase"."accounting_journals" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."accounting_journals" drop constraint if exists "bsb_accounting_journals_legal_entity_fk";
alter table "better_supabase"."accounting_journals" add constraint "bsb_accounting_journals_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_accounting_journals_legal_entity_idx" on "better_supabase"."accounting_journals" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
alter table "better_supabase"."accounting_entries" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."accounting_entries" drop constraint if exists "bsb_accounting_entries_legal_entity_fk";
alter table "better_supabase"."accounting_entries" add constraint "bsb_accounting_entries_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_accounting_entries_legal_entity_idx" on "better_supabase"."accounting_entries" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
alter table "better_supabase"."inventory_locations" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."inventory_locations" drop constraint if exists "bsb_inventory_locations_legal_entity_fk";
alter table "better_supabase"."inventory_locations" add constraint "bsb_inventory_locations_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_inventory_locations_legal_entity_idx" on "better_supabase"."inventory_locations" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
alter table "better_supabase"."organization_settings" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."organization_settings" drop constraint if exists "bsb_organization_settings_legal_entity_fk";
alter table "better_supabase"."organization_settings" add constraint "bsb_organization_settings_legal_entity_fk" foreign key ("organization_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_organization_settings_legal_entity_idx" on "better_supabase"."organization_settings" ("organization_id", legal_entity_id) where legal_entity_id is not null;
alter table "better_supabase"."field_values" add column if not exists legal_entity_id uuid;
alter table "better_supabase"."field_values" drop constraint if exists "bsb_field_values_legal_entity_fk";
alter table "better_supabase"."field_values" add constraint "bsb_field_values_legal_entity_fk" foreign key ("tenant_id", legal_entity_id) references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict;
create index if not exists "bsb_field_values_legal_entity_idx" on "better_supabase"."field_values" ("tenant_id", legal_entity_id) where legal_entity_id is not null;
do $$
declare
  v_constraint name;
begin
  for v_constraint in
    select c.conname from pg_constraint c
    where c.conrelid = '"better_supabase"."field_values"'::regclass and c.contype = 'u'
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any (c.conkey))
        @> array['tenant_id', 'subject_type', 'subject_id', 'definition_id']
      and cardinality(c.conkey) = 4
  loop
    execute format('alter table "better_supabase"."field_values" drop constraint %I', v_constraint);
  end loop;
end $$;
create unique index if not exists "bsb_field_values_entity_key_idx" on "better_supabase"."field_values" ("tenant_id", "subject_type", "subject_id", "definition_id", coalesce(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid));


-- Checks the fiscal settings and fills the defaults: the first month of the
-- fiscal year (1 to 12) and the tax period (monthly or quarterly).
create or replace function "better_supabase"."legal_entity_fiscal"(fiscal jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_month text;
  v_period text;
begin
  if legal_entity_fiscal.fiscal is null or jsonb_typeof(legal_entity_fiscal.fiscal) <> 'object' then
    raise exception 'fiscal must be an object' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  v_month := coalesce(legal_entity_fiscal.fiscal ->> 'fiscalYearStartMonth', '1');
  v_period := coalesce(legal_entity_fiscal.fiscal ->> 'taxPeriod', 'quarterly');
  if v_month !~ '^[0-9]{1,2}$' or v_month::integer < 1 or v_month::integer > 12 then
    raise exception 'fiscalYearStartMonth must be a month from 1 to 12' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  if v_period not in ('monthly', 'quarterly') then
    raise exception 'taxPeriod must be monthly or quarterly' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  return jsonb_build_object('fiscalYearStartMonth', v_month::integer, 'taxPeriod', v_period);
end;
$$;
revoke execute on function "better_supabase"."legal_entity_fiscal"(jsonb) from public, anon, authenticated;

-- Creates a legal entity. The first entity of an organization becomes its
-- default, and is_default makes a later one the default instead.
create or replace function "better_supabase"."create_legal_entity"(tenant uuid, code text, name text, address jsonb default null, vat_number text default null, coc_number text default null, iban text default null, bic text default null, logo_attachment_id uuid default null, default_currency text default null, fiscal jsonb default null, is_default boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."legal_entities"%rowtype;
  v_default boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_legal_entity.tenant, 'legal_entities.manage'), false)) then
    raise exception 'not allowed to manage legal entities' using errcode = '42501', hint = 'LEGAL_ENTITY_FORBIDDEN';
  end if;
  if nullif(trim(create_legal_entity.code), '') is null or nullif(trim(create_legal_entity.name), '') is null then
    raise exception 'a legal entity needs a code and a name' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_legal_entity_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using create_legal_entity.tenant;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('legal_entities:' || create_legal_entity.tenant::text, 0));
  if exists (select 1 from "better_supabase"."legal_entities" x where x."tenant_id" = create_legal_entity.tenant and x."code" = trim(create_legal_entity.code)) then
    raise exception 'a legal entity with this code exists' using errcode = '23505', hint = 'LEGAL_ENTITY_CODE_TAKEN';
  end if;
  v_default := coalesce(create_legal_entity.is_default, false)
    or not exists (select 1 from "better_supabase"."legal_entities" x where x."tenant_id" = create_legal_entity.tenant and x."is_default");
  if v_default then
    update "better_supabase"."legal_entities" x set "is_default" = false, "updated_at" = now()
      where x."tenant_id" = create_legal_entity.tenant and x."is_default";
  end if;
  insert into "better_supabase"."legal_entities" ("tenant_id", "code", "name", "address", "vat_number", "coc_number", "iban", "bic", "logo_attachment_id", "default_currency", "fiscal", "is_default")
  values (create_legal_entity.tenant, trim(create_legal_entity.code), trim(create_legal_entity.name), coalesce(create_legal_entity.address, '{}'::jsonb),
    nullif(trim(create_legal_entity.vat_number), ''), nullif(trim(create_legal_entity.coc_number), ''), nullif(replace(trim(create_legal_entity.iban), ' ', ''), ''), nullif(trim(create_legal_entity.bic), ''),
    create_legal_entity.logo_attachment_id, nullif(upper(trim(create_legal_entity.default_currency)), ''),
    "better_supabase"."legal_entity_fiscal"(coalesce(create_legal_entity.fiscal, '{}'::jsonb)), v_default)
  returning * into v_row;
  perform "better_supabase".emit_event('legal_entity.created', jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default"), 'legal-entities/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/legal-entities');
  perform better_supabase.audit_event(
    event_type => 'legal_entity.created',
    category => 'data',
    target_type => 'legal_entity',
    record_id => v_row."id"::text,
    summary => 'created legal entity ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_legal_entity_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'address', v_row."address", 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency", 'fiscal', v_row."fiscal", 'isDefault', v_row."is_default", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_legal_entity"(uuid, text, text, jsonb, text, text, text, text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."create_legal_entity"(uuid, text, text, jsonb, text, text, text, text, uuid, text, jsonb, boolean) to authenticated, service_role;

-- Changes the keys present in patch (code, name, address, vat_number,
-- coc_number, iban, bic, logo_attachment_id, default_currency, fiscal).
create or replace function "better_supabase"."update_legal_entity"(legal_entity_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."legal_entities"%rowtype;
  v_old "better_supabase"."legal_entities"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_old from "better_supabase"."legal_entities" x where x."id" = update_legal_entity.legal_entity_id;
  if not found then
    raise exception 'legal entity not found' using errcode = 'P0002', hint = 'LEGAL_ENTITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'legal_entities.manage'), false)) then
    raise exception 'not allowed to manage legal entities' using errcode = '42501', hint = 'LEGAL_ENTITY_FORBIDDEN';
  end if;
  if update_legal_entity.patch is null or jsonb_typeof(update_legal_entity.patch) <> 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_legal_entity_update"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using update_legal_entity.legal_entity_id;
    end if;
  end;
  if update_legal_entity.patch ? 'code' and nullif(trim(update_legal_entity.patch ->> 'code'), '') is null then
    raise exception 'code can''t be empty' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  if update_legal_entity.patch ? 'name' and nullif(trim(update_legal_entity.patch ->> 'name'), '') is null then
    raise exception 'name can''t be empty' using errcode = '22023', hint = 'LEGAL_ENTITY_INVALID';
  end if;
  if update_legal_entity.patch ? 'code' and exists (
    select 1 from "better_supabase"."legal_entities" x
    where x."tenant_id" = v_old."tenant_id" and x."code" = trim(update_legal_entity.patch ->> 'code') and x."id" <> v_old."id"
  ) then
    raise exception 'a legal entity with this code exists' using errcode = '23505', hint = 'LEGAL_ENTITY_CODE_TAKEN';
  end if;
  update "better_supabase"."legal_entities" x set
    "code" = case when update_legal_entity.patch ? 'code' then trim(update_legal_entity.patch ->> 'code') else x."code" end,
    "name" = case when update_legal_entity.patch ? 'name' then trim(update_legal_entity.patch ->> 'name') else x."name" end,
    "address" = case when update_legal_entity.patch ? 'address' then coalesce(update_legal_entity.patch -> 'address', '{}'::jsonb) else x."address" end,
    "vat_number" = case when update_legal_entity.patch ? 'vat_number' then nullif(trim(update_legal_entity.patch ->> 'vat_number'), '') else x."vat_number" end,
    "coc_number" = case when update_legal_entity.patch ? 'coc_number' then nullif(trim(update_legal_entity.patch ->> 'coc_number'), '') else x."coc_number" end,
    "iban" = case when update_legal_entity.patch ? 'iban' then nullif(replace(trim(update_legal_entity.patch ->> 'iban'), ' ', ''), '') else x."iban" end,
    "bic" = case when update_legal_entity.patch ? 'bic' then nullif(trim(update_legal_entity.patch ->> 'bic'), '') else x."bic" end,
    "logo_attachment_id" = case when update_legal_entity.patch ? 'logo_attachment_id' then nullif(update_legal_entity.patch ->> 'logo_attachment_id', '')::uuid else x."logo_attachment_id" end,
    "default_currency" = case when update_legal_entity.patch ? 'default_currency' then nullif(upper(trim(update_legal_entity.patch ->> 'default_currency')), '') else x."default_currency" end,
    "fiscal" = case when update_legal_entity.patch ? 'fiscal' then "better_supabase"."legal_entity_fiscal"(x."fiscal" || coalesce(update_legal_entity.patch -> 'fiscal', '{}'::jsonb)) else x."fiscal" end,
    "updated_at" = now()
  where x."id" = v_old."id"
  returning * into v_row;
  perform "better_supabase".emit_event('legal_entity.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default"), 'legal-entities/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/legal-entities');
  perform better_supabase.audit_event(
    event_type => 'legal_entity.updated',
    category => 'data',
    target_type => 'legal_entity',
    record_id => v_row."id"::text,
    summary => 'updated legal entity ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_legal_entity_update"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'address', v_row."address", 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency", 'fiscal', v_row."fiscal", 'isDefault', v_row."is_default", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_legal_entity"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_legal_entity"(uuid, jsonb) to authenticated, service_role;

-- Makes an active legal entity the organization's default.
create or replace function "better_supabase"."set_default_legal_entity"(legal_entity_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."legal_entities"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."legal_entities" x where x."id" = set_default_legal_entity.legal_entity_id;
  if not found then
    raise exception 'legal entity not found' using errcode = 'P0002', hint = 'LEGAL_ENTITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'legal_entities.manage'), false)) then
    raise exception 'not allowed to manage legal entities' using errcode = '42501', hint = 'LEGAL_ENTITY_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('legal_entities:' || v_row."tenant_id"::text, 0));
  if v_row."archived_at" is not null then
    raise exception 'an archived legal entity can''t be the default' using errcode = '22023', hint = 'LEGAL_ENTITY_ARCHIVED';
  end if;
  update "better_supabase"."legal_entities" x set "is_default" = false, "updated_at" = now()
    where x."tenant_id" = v_row."tenant_id" and x."is_default" and x."id" <> v_row."id";
  update "better_supabase"."legal_entities" x set "is_default" = true, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('legal_entity.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default"), 'legal-entities/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/legal-entities');
  perform better_supabase.audit_event(
    event_type => 'legal_entity.updated',
    category => 'data',
    target_type => 'legal_entity',
    record_id => v_row."id"::text,
    summary => 'made legal entity ' || v_row."code" || ' the default',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'address', v_row."address", 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency", 'fiscal', v_row."fiscal", 'isDefault', v_row."is_default", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_default_legal_entity"(uuid) from public, anon;
grant execute on function "better_supabase"."set_default_legal_entity"(uuid) to authenticated, service_role;

-- Archives a legal entity, or restores it. The default can't be archived:
-- make another one the default first.
create or replace function "better_supabase"."set_legal_entity_archived"(legal_entity_id uuid, archived boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."legal_entities"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."legal_entities" x where x."id" = set_legal_entity_archived.legal_entity_id;
  if not found then
    raise exception 'legal entity not found' using errcode = 'P0002', hint = 'LEGAL_ENTITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'legal_entities.manage'), false)) then
    raise exception 'not allowed to manage legal entities' using errcode = '42501', hint = 'LEGAL_ENTITY_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('legal_entities:' || v_row."tenant_id"::text, 0));
  if coalesce(set_legal_entity_archived.archived, true) and v_row."is_default" then
    raise exception 'make another legal entity the default before archiving this one' using errcode = '22023', hint = 'LEGAL_ENTITY_DEFAULT';
  end if;
  update "better_supabase"."legal_entities" x set
    "archived_at" = case when coalesce(set_legal_entity_archived.archived, true) then coalesce(x."archived_at", now()) else null end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('legal_entity.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default"), 'legal-entities/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/legal-entities');
  perform better_supabase.audit_event(
    event_type => 'legal_entity.updated',
    category => 'data',
    target_type => 'legal_entity',
    record_id => v_row."id"::text,
    summary => case when v_row."archived_at" is null then 'restored legal entity ' else 'archived legal entity ' end || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'legalEntityId', v_row."id", 'code', v_row."code", 'isDefault', v_row."is_default")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'address', v_row."address", 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency", 'fiscal', v_row."fiscal", 'isDefault', v_row."is_default", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_legal_entity_archived"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_legal_entity_archived"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."get_legal_entity"(legal_entity_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."legal_entities"%rowtype;
begin
  select * into v_row from "better_supabase"."legal_entities" x where x."id" = get_legal_entity.legal_entity_id;
  if not found then
    raise exception 'legal entity not found' using errcode = 'P0002', hint = 'LEGAL_ENTITY_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'address', v_row."address", 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency", 'fiscal', v_row."fiscal", 'isDefault', v_row."is_default", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_legal_entity"(uuid) from public, anon;
grant execute on function "better_supabase"."get_legal_entity"(uuid) to authenticated, service_role;

-- The default entity first, then by code.
create or replace function "better_supabase"."list_legal_entities"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'address', x."address", 'vatNumber', x."vat_number", 'cocNumber', x."coc_number", 'iban', x."iban", 'bic', x."bic", 'logoAttachmentId', x."logo_attachment_id", 'defaultCurrency', x."default_currency", 'fiscal', x."fiscal", 'isDefault', x."is_default", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."is_default" desc, x."code"), '[]'::jsonb)
  from "better_supabase"."legal_entities" x
  where x."tenant_id" = list_legal_entities.tenant
    and (coalesce(list_legal_entities.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_legal_entities"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_legal_entities"(uuid, boolean) to authenticated, service_role;

-- The legal entity a row belongs to: the given one when it is the
-- organization's, otherwise the organization's default. Null means the
-- organization has no legal entity yet, which is how a single-entity
-- organization runs with no configuration. Other modules call this with a
-- legal_entity_id column that may be null.
create or replace function "better_supabase"."legal_entity_of"(tenant uuid, id uuid default null)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if legal_entity_of.id is not null then
    select x."id" into v_id from "better_supabase"."legal_entities" x
      where x."id" = legal_entity_of.id and x."tenant_id" = legal_entity_of.tenant;
    if v_id is null then
      raise exception 'legal entity not found' using errcode = 'P0002', hint = 'LEGAL_ENTITY_NOT_FOUND';
    end if;
    return v_id;
  end if;
  select x."id" into v_id from "better_supabase"."legal_entities" x
    where x."tenant_id" = legal_entity_of.tenant and x."is_default";
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."legal_entity_of"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."legal_entity_of"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_legal_entity_settings"(legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."legal_entity_settings" s
  where s."legal_entity_id" = get_legal_entity_settings.legal_entity_id
$$;
revoke execute on function "better_supabase"."get_legal_entity_settings"(uuid) from public, anon;
grant execute on function "better_supabase"."get_legal_entity_settings"(uuid) to authenticated, service_role;

-- Stores one setting of a legal entity. value takes the same envelope as
-- set_organization_setting: { "value": ... }.
create or replace function "better_supabase"."set_legal_entity_setting"(legal_entity_id uuid, key text, value jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_value jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."legal_entities" x where x."id" = set_legal_entity_setting.legal_entity_id;
  if v_tenant is null then
    raise exception 'legal entity not found' using errcode = 'P0002', hint = 'LEGAL_ENTITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'legal_entities.manage'), false)) then
    raise exception 'not allowed to manage legal entities' using errcode = '42501', hint = 'LEGAL_ENTITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."legal_entity_settings" ("tenant_id", "legal_entity_id", "key", "value")
  values (v_tenant, set_legal_entity_setting.legal_entity_id, set_legal_entity_setting.key, coalesce(set_legal_entity_setting.value -> 'value', 'null'::jsonb))
  on conflict ("legal_entity_id", "key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value" into v_value;
  return v_value;
end;
$$;
revoke execute on function "better_supabase"."set_legal_entity_setting"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."set_legal_entity_setting"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."reset_legal_entity_setting"(legal_entity_id uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."legal_entities" x where x."id" = reset_legal_entity_setting.legal_entity_id;
  if v_tenant is null then
    raise exception 'legal entity not found' using errcode = 'P0002', hint = 'LEGAL_ENTITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'legal_entities.manage'), false)) then
    raise exception 'not allowed to manage legal entities' using errcode = '42501', hint = 'LEGAL_ENTITY_FORBIDDEN';
  end if;
  delete from "better_supabase"."legal_entity_settings" s
    where s."legal_entity_id" = reset_legal_entity_setting.legal_entity_id and s."key" = reset_legal_entity_setting.key;
  return found;
end;
$$;
revoke execute on function "better_supabase"."reset_legal_entity_setting"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reset_legal_entity_setting"(uuid, text) to authenticated, service_role;

-- One setting for a legal entity: its own value, else the organization's
-- value, else { "source": "default", "value": null }, where the caller applies
-- the code default. Without a legal entity the organization's default entity
-- answers. Reads as the caller, so the settings the caller may not read count
-- as unset.
create or replace function "better_supabase"."resolve_setting"(tenant uuid, key text, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entity uuid;
  v_value jsonb;
begin
  v_entity := "better_supabase"."legal_entity_of"(resolve_setting.tenant, resolve_setting.legal_entity);
  if v_entity is not null then
    select s."value" into v_value from "better_supabase"."legal_entity_settings" s
      where s."legal_entity_id" = v_entity and s."key" = resolve_setting.key;
    if found then
      return jsonb_build_object('value', v_value, 'source', 'legal_entity', 'legalEntityId', v_entity);
    end if;
  end if;
  select s."value" into v_value from "better_supabase"."organization_settings" s
    where s."organization_id" = resolve_setting.tenant and s."key" = resolve_setting.key;
  if found then
    return jsonb_build_object('value', v_value, 'source', 'organization', 'legalEntityId', v_entity);
  end if;
  return jsonb_build_object('value', null, 'source', 'default', 'legalEntityId', v_entity);
end;
$$;
revoke execute on function "better_supabase"."resolve_setting"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."resolve_setting"(uuid, text, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."legal_entities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."legal_entities";
create policy bsb_tenant_scope_select on "better_supabase"."legal_entities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('legal_entities.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."legal_entities";
create policy bsb_tenant_scope_insert on "better_supabase"."legal_entities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."legal_entities";
create policy bsb_tenant_scope_update on "better_supabase"."legal_entities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."legal_entities";
create policy bsb_tenant_scope_delete on "better_supabase"."legal_entities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."legal_entity_settings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."legal_entity_settings";
create policy bsb_tenant_scope_select on "better_supabase"."legal_entity_settings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('legal_entities.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."legal_entity_settings";
create policy bsb_tenant_scope_insert on "better_supabase"."legal_entity_settings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."legal_entity_settings";
create policy bsb_tenant_scope_update on "better_supabase"."legal_entity_settings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."legal_entity_settings";
create policy bsb_tenant_scope_delete on "better_supabase"."legal_entity_settings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.legal-entities.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."create_legal_entity"(tenant uuid, code text, name text, address jsonb default null, vat_number text default null, coc_number text default null, iban text default null, bic text default null, logo_attachment_id uuid default null, default_currency text default null, fiscal jsonb default null, is_default boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_legal_entity"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $$;
revoke execute on function "api"."create_legal_entity"(uuid, text, text, jsonb, text, text, text, text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "api"."create_legal_entity"(uuid, text, text, jsonb, text, text, text, text, uuid, text, jsonb, boolean) to authenticated, service_role;

create or replace function "api"."update_legal_entity"(legal_entity_id uuid, patch jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_legal_entity"($1, $2) $$;
revoke execute on function "api"."update_legal_entity"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_legal_entity"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_default_legal_entity"(legal_entity_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_default_legal_entity"($1) $$;
revoke execute on function "api"."set_default_legal_entity"(uuid) from public, anon;
grant execute on function "api"."set_default_legal_entity"(uuid) to authenticated, service_role;

create or replace function "api"."set_legal_entity_archived"(legal_entity_id uuid, archived boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_legal_entity_archived"($1, $2) $$;
revoke execute on function "api"."set_legal_entity_archived"(uuid, boolean) from public, anon;
grant execute on function "api"."set_legal_entity_archived"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."get_legal_entity"(legal_entity_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_legal_entity"($1) $$;
revoke execute on function "api"."get_legal_entity"(uuid) from public, anon;
grant execute on function "api"."get_legal_entity"(uuid) to authenticated, service_role;

create or replace function "api"."list_legal_entities"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_legal_entities"($1, $2) $$;
revoke execute on function "api"."list_legal_entities"(uuid, boolean) from public, anon;
grant execute on function "api"."list_legal_entities"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."legal_entity_of"(tenant uuid, id uuid default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."legal_entity_of"($1, $2) $$;
revoke execute on function "api"."legal_entity_of"(uuid, uuid) from public, anon;
grant execute on function "api"."legal_entity_of"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."get_legal_entity_settings"(legal_entity_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_legal_entity_settings"($1) $$;
revoke execute on function "api"."get_legal_entity_settings"(uuid) from public, anon;
grant execute on function "api"."get_legal_entity_settings"(uuid) to authenticated, service_role;

create or replace function "api"."set_legal_entity_setting"(legal_entity_id uuid, key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_legal_entity_setting"($1, $2, $3) $$;
revoke execute on function "api"."set_legal_entity_setting"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."set_legal_entity_setting"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."reset_legal_entity_setting"(legal_entity_id uuid, key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reset_legal_entity_setting"($1, $2) $$;
revoke execute on function "api"."reset_legal_entity_setting"(uuid, text) from public, anon;
grant execute on function "api"."reset_legal_entity_setting"(uuid, text) to authenticated, service_role;

create or replace function "api"."resolve_setting"(tenant uuid, key text, legal_entity uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_setting"($1, $2, $3) $$;
revoke execute on function "api"."resolve_setting"(uuid, text, uuid) from public, anon;
grant execute on function "api"."resolve_setting"(uuid, text, uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
