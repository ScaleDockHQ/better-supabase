-- ==== schema supabase/schemas/900_better_supabase_172_advisories.sql
-- better-supabase module: advisories
-- @bsb-block advisories@1 managed
-- @bsb-hash sha256:bba5d355db41b59f96a0731cf7a1ef732638c74e24fb38d0ac5935fc7fba5976
-- Security advisories for a software vendor: products and versions with CycloneDX components, vulnerabilities enriched from OSV, EPSS and the CISA KEV catalog on a schedule, OpenVEX statements per version, and CSAF 2.0 advisories with a /.well-known/csaf handler, linked to incidents and risks through relations.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."advisory_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisory_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisory_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisory_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisory_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."advisory_product_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisory_product_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisory_product_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisory_product_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisory_product_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."sbom_components";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."sbom_components";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."sbom_components";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."sbom_components";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."sbom_components";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."vulnerabilities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."vulnerabilities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."vulnerabilities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."vulnerabilities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."vulnerabilities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."vex_statements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."vex_statements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."vex_statements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."vex_statements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."vex_statements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."advisories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."advisory_vulnerabilities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisory_vulnerabilities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisory_vulnerabilities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisory_vulnerabilities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisory_vulnerabilities";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Security advisories for a software vendor: products and versions with their
-- CycloneDX components, vulnerabilities enriched from OSV, EPSS and the CISA KEV
-- catalog, OpenVEX statements per version and CSAF 2.0 advisories.

create table if not exists "better_supabase"."advisory_products" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- Names the product in OpenVEX and CSAF documents.
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9._-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "vendor" text check ("vendor" is null or length("vendor") <= 200),
  "description" text check ("description" is null or length("description") <= 5000),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "advisory_products_key_idx" on "better_supabase"."advisory_products" ("tenant_id", "key");
alter table "better_supabase"."advisory_products" enable row level security;
revoke all on "better_supabase"."advisory_products" from public, anon, authenticated;
grant select on "better_supabase"."advisory_products" to authenticated;
grant all on "better_supabase"."advisory_products" to service_role;
drop policy if exists advisory_products_read on "better_supabase"."advisory_products";
create policy advisory_products_read on "better_supabase"."advisory_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')));

create table if not exists "better_supabase"."advisory_product_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "product_id" uuid not null,
  "version" text not null check (length("version") between 1 and 100),
  "released_at" timestamptz,
  "end_of_support_at" timestamptz,
  -- The BOM the components came from: its urn:uuid serial and CycloneDX version.
  "sbom_serial" text,
  "sbom_spec" text,
  "sbom_component_count" integer not null default 0,
  "sbom_imported_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "advisory_product_versions_product_idx" on "better_supabase"."advisory_product_versions" ("tenant_id", "product_id", "version");
alter table "better_supabase"."advisory_product_versions" enable row level security;
revoke all on "better_supabase"."advisory_product_versions" from public, anon, authenticated;
grant select on "better_supabase"."advisory_product_versions" to authenticated;
grant all on "better_supabase"."advisory_product_versions" to service_role;
drop policy if exists advisory_product_versions_read on "better_supabase"."advisory_product_versions";
create policy advisory_product_versions_read on "better_supabase"."advisory_product_versions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')));

create table if not exists "better_supabase"."sbom_components" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "version_id" uuid not null,
  "bom_ref" text,
  "component_type" text not null default 'library',
  "name" text not null check (length("name") between 1 and 500),
  "component_version" text,
  "purl" text,
  -- The purl without version, qualifiers and subpath, which vulnerabilities match on.
  "package_purl" text,
  "cpe" text,
  "supplier" text,
  "licenses" text[] not null default '{}',
  "hashes" jsonb not null default '[]'
);
create index if not exists "sbom_components_version_idx" on "better_supabase"."sbom_components" ("tenant_id", "version_id");
create index if not exists "sbom_components_package_idx" on "better_supabase"."sbom_components" ("tenant_id", "package_purl") where "package_purl" is not null;
alter table "better_supabase"."sbom_components" enable row level security;
revoke all on "better_supabase"."sbom_components" from public, anon, authenticated;
grant select on "better_supabase"."sbom_components" to authenticated;
grant all on "better_supabase"."sbom_components" to service_role;
drop policy if exists sbom_components_read on "better_supabase"."sbom_components";
create policy sbom_components_read on "better_supabase"."sbom_components"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')));

create table if not exists "better_supabase"."vulnerabilities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "vuln_id" text not null check ("vuln_id" ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$'),
  "aliases" text[] not null default '{}',
  "summary" text check ("summary" is null or length("summary") <= 1000),
  "details" text check ("details" is null or length("details") <= 20000),
  "cvss_vector" text check ("cvss_vector" is null or length("cvss_vector") <= 300),
  "cvss_version" text check ("cvss_version" is null or "cvss_version" in ('3.0', '3.1', '4.0')),
  "cvss_score" numeric(3, 1) check ("cvss_score" is null or "cvss_score" between 0 and 10),
  "severity" text check ("severity" is null or "severity" in ('none', 'low', 'medium', 'high', 'critical')),
  "epss_score" numeric(6, 5) check ("epss_score" is null or "epss_score" between 0 and 1),
  "epss_percentile" numeric(6, 5) check ("epss_percentile" is null or "epss_percentile" between 0 and 1),
  "epss_date" date,
  "kev" boolean not null default false,
  "kev_added_on" date,
  "kev_due_on" date,
  "kev_ransomware" boolean not null default false,
  -- Package URLs without a version, from OSV; exposure matches components on them.
  "affected_purls" text[] not null default '{}',
  "reference_links" jsonb not null default '[]',
  "published_at" timestamptz,
  "modified_at" timestamptz,
  "enriched_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "vulnerabilities_vuln_idx" on "better_supabase"."vulnerabilities" ("tenant_id", "vuln_id");
create index if not exists "vulnerabilities_purls_idx" on "better_supabase"."vulnerabilities" using gin ("affected_purls");
create index if not exists "vulnerabilities_due_idx" on "better_supabase"."vulnerabilities" ("enriched_at" nulls first);
alter table "better_supabase"."vulnerabilities" enable row level security;
revoke all on "better_supabase"."vulnerabilities" from public, anon, authenticated;
grant select on "better_supabase"."vulnerabilities" to authenticated;
grant all on "better_supabase"."vulnerabilities" to service_role;
drop policy if exists vulnerabilities_read on "better_supabase"."vulnerabilities";
create policy vulnerabilities_read on "better_supabase"."vulnerabilities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')));

create table if not exists "better_supabase"."vex_statements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "product_id" uuid not null,
  -- Null: the statement covers every version of the product.
  "version_id" uuid,
  "vulnerability_id" uuid not null,
  "status" text not null check ("status" in ('not_affected', 'affected', 'fixed', 'under_investigation')),
  "justification" text check ("justification" is null or "justification" in ('component_not_present', 'vulnerable_code_not_present', 'vulnerable_code_not_in_execute_path', 'vulnerable_code_cannot_be_controlled_by_adversary', 'inline_mitigations_already_exist')),
  "impact_statement" text check ("impact_statement" is null or length("impact_statement") <= 5000),
  "action_statement" text check ("action_statement" is null or length("action_statement") <= 5000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "vex_statements_scope_idx" on "better_supabase"."vex_statements" ("tenant_id", "product_id", "vulnerability_id", coalesce("version_id", '00000000-0000-0000-0000-000000000000'::uuid));
alter table "better_supabase"."vex_statements" enable row level security;
revoke all on "better_supabase"."vex_statements" from public, anon, authenticated;
grant select on "better_supabase"."vex_statements" to authenticated;
grant all on "better_supabase"."vex_statements" to service_role;
drop policy if exists vex_statements_read on "better_supabase"."vex_statements";
create policy vex_statements_read on "better_supabase"."vex_statements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')));

create table if not exists "better_supabase"."advisories" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The CSAF tracking id, such as ACME-SA-2026-001.
  "tracking_id" text not null check ("tracking_id" ~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$'),
  "title" text not null check (length("title") between 1 and 300),
  "summary" text check ("summary" is null or length("summary") <= 10000),
  "product_id" uuid not null,
  "severity" text check ("severity" is null or "severity" in ('none', 'low', 'medium', 'high', 'critical')),
  "status" text not null default 'draft' check ("status" in ('draft', 'interim', 'final')),
  -- The CSAF document version: 0 for a draft, then one more per publication.
  "revision" integer not null default 0 check ("revision" >= 0),
  "initial_release_at" timestamptz,
  "current_release_at" timestamptz,
  -- [{ number, date, summary }], one entry per publication.
  "revision_history" jsonb not null default '[]' check (jsonb_typeof("revision_history") = 'array'),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "advisories_tracking_idx" on "better_supabase"."advisories" ("tenant_id", "tracking_id");
create index if not exists "advisories_status_idx" on "better_supabase"."advisories" ("tenant_id", "status", "created_at" desc);
alter table "better_supabase"."advisories" enable row level security;
revoke all on "better_supabase"."advisories" from public, anon, authenticated;
grant select on "better_supabase"."advisories" to authenticated;
grant all on "better_supabase"."advisories" to service_role;
drop policy if exists advisories_read on "better_supabase"."advisories";
create policy advisories_read on "better_supabase"."advisories"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')));

create table if not exists "better_supabase"."advisory_vulnerabilities" (
  "tenant_id" uuid not null,
  "advisory_id" uuid not null,
  "vulnerability_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("advisory_id", "vulnerability_id")
);
create index if not exists "advisory_vulnerabilities_vuln_idx" on "better_supabase"."advisory_vulnerabilities" ("tenant_id", "vulnerability_id");
alter table "better_supabase"."advisory_vulnerabilities" enable row level security;
revoke all on "better_supabase"."advisory_vulnerabilities" from public, anon, authenticated;
grant select on "better_supabase"."advisory_vulnerabilities" to authenticated;
grant all on "better_supabase"."advisory_vulnerabilities" to service_role;
drop policy if exists advisory_vulnerabilities_read on "better_supabase"."advisory_vulnerabilities";
create policy advisory_vulnerabilities_read on "better_supabase"."advisory_vulnerabilities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')));


-- The organization's products, the newest first.
create or replace function "better_supabase"."list_advisory_products"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_advisory_products.tenant is not null and coalesce(better_supabase.can('tenant', list_advisory_products.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'key', y."key", 'name', y."name", 'vendor', y."vendor", 'description', y."description", 'archivedAt', y."archived_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc)
    from "better_supabase"."advisory_products" y where y."tenant_id" = list_advisory_products.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_advisory_products"(uuid) from public, anon;
grant execute on function "better_supabase"."list_advisory_products"(uuid) to authenticated, service_role;

-- Creates a product or, with product_id, changes one. The key is lowercase
-- letters, digits, dots, dashes and underscores; it names the product in OpenVEX
-- and CSAF documents. archived true takes the product off the lists.
create or replace function "better_supabase"."save_advisory_product"(tenant uuid, key text, name text, vendor text default null, description text default null, archived boolean default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."advisory_products";
  v_old "better_supabase"."advisory_products";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_advisory_product.tenant is not null and coalesce(better_supabase.can('tenant', save_advisory_product.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if coalesce(save_advisory_product.key, '') !~ '^[a-z0-9][a-z0-9._-]{0,62}$' then
    raise exception 'key must be lowercase letters, digits, dots, dashes and underscores, 1 to 63 characters' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if coalesce(length(trim(save_advisory_product.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if length(save_advisory_product.vendor) > 200 or length(save_advisory_product.description) > 5000 then
    raise exception 'vendor is at most 200 characters and description at most 5000' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if save_advisory_product.product_id is not null then
    select * into v_old from "better_supabase"."advisory_products" y
    where y."id" = save_advisory_product.product_id and y."tenant_id" = save_advisory_product.tenant
    for update;
    if not found then
      raise exception 'no such product in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
    end if;
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."advisory_products" ("tenant_id", "key", "name", "vendor", "description", "created_by")
    values (save_advisory_product.tenant, save_advisory_product.key, trim(save_advisory_product.name), nullif(trim(save_advisory_product.vendor), ''), nullif(trim(save_advisory_product.description), ''), (select auth.uid()))
    returning * into v_row;
    null;
  else
    update "better_supabase"."advisory_products" y set
      "key" = save_advisory_product.key,
      "name" = trim(save_advisory_product.name),
      "vendor" = nullif(trim(save_advisory_product.vendor), ''),
      "description" = nullif(trim(save_advisory_product.description), ''),
      "archived_at" = case
        when save_advisory_product.archived is null then y."archived_at"
        when save_advisory_product.archived then coalesce(y."archived_at", now())
        else null end,
      "updated_at" = now()
    where y."id" = v_old."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'vendor', v_row."vendor", 'description', v_row."description", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another product of this organization has this key' using errcode = '22023', hint = 'ADVISORY_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_advisory_product"(uuid, text, text, text, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_advisory_product"(uuid, text, text, text, text, boolean, uuid) to authenticated, service_role;

-- Adds a version to a product. Versions are free text, such as 2.4.1.
create or replace function "better_supabase"."create_product_version"(tenant uuid, product_id uuid, version text, released_at timestamptz default null, end_of_support_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."advisory_product_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_product_version.tenant is not null and coalesce(better_supabase.can('tenant', create_product_version.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if coalesce(length(trim(create_product_version.version)), 0) not between 1 and 100 then
    raise exception 'version must be 1 to 100 characters' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."advisory_products" y
    where y."id" = create_product_version.product_id and y."tenant_id" = create_product_version.tenant
  ) then
    raise exception 'no such product in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  insert into "better_supabase"."advisory_product_versions" ("tenant_id", "product_id", "version", "released_at", "end_of_support_at")
  values (create_product_version.tenant, create_product_version.product_id, trim(create_product_version.version), create_product_version.released_at, create_product_version.end_of_support_at)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'productId', v_row."product_id", 'version', v_row."version", 'releasedAt', v_row."released_at", 'endOfSupportAt', v_row."end_of_support_at", 'sbomSerial', v_row."sbom_serial", 'sbomSpec', v_row."sbom_spec", 'sbomComponents', v_row."sbom_component_count", 'sbomImportedAt', v_row."sbom_imported_at", 'createdAt', v_row."created_at");
exception when unique_violation then
  raise exception 'this product already has this version' using errcode = '22023', hint = 'ADVISORY_INVALID';
end;
$$;
revoke execute on function "better_supabase"."create_product_version"(uuid, uuid, text, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_product_version"(uuid, uuid, text, timestamptz, timestamptz) to authenticated, service_role;

-- The versions of a product, the newest first.
create or replace function "better_supabase"."list_product_versions"(tenant uuid, product_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_product_versions.tenant is not null and coalesce(better_supabase.can('tenant', list_product_versions.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'productId', y."product_id", 'version', y."version", 'releasedAt', y."released_at", 'endOfSupportAt', y."end_of_support_at", 'sbomSerial', y."sbom_serial", 'sbomSpec', y."sbom_spec", 'sbomComponents', y."sbom_component_count", 'sbomImportedAt', y."sbom_imported_at", 'createdAt', y."created_at") order by y."created_at" desc, y."version")
    from "better_supabase"."advisory_product_versions" y
    where y."tenant_id" = list_product_versions.tenant and y."product_id" = list_product_versions.product_id
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_product_versions"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."list_product_versions"(uuid, uuid) to authenticated, service_role;

-- Replaces the components of a version with a parsed CycloneDX BOM. components
-- is [{ bomRef, type, name, version, purl, cpe, supplier, licenses, hashes }];
-- the TypeScript client parses the document, this function validates and stores
-- the result. package_purl is the purl without version, qualifiers and subpath,
-- the key vulnerabilities match on.
create or replace function "better_supabase"."import_sbom"(tenant uuid, version_id uuid, components jsonb, serial_number text default null, spec_version text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."advisory_product_versions";
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (import_sbom.tenant is not null and coalesce(better_supabase.can('tenant', import_sbom.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if jsonb_typeof(import_sbom.components) is distinct from 'array' or jsonb_array_length(import_sbom.components) > 20000 then
    raise exception 'components must be a list of at most 20000 components, each with a name' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(import_sbom.components) e
    where jsonb_typeof(e) <> 'object' or coalesce(length(trim(e ->> 'name')), 0) not between 1 and 500
      or length(e ->> 'purl') > 2000 or length(e ->> 'version') > 200
      or (e ? 'licenses' and jsonb_typeof(e -> 'licenses') <> 'array')
      or (e ? 'hashes' and jsonb_typeof(e -> 'hashes') <> 'array')
  ) then
    raise exception 'components must be a list of at most 20000 components, each with a name' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select * into v_row from "better_supabase"."advisory_product_versions" y
  where y."id" = import_sbom.version_id and y."tenant_id" = import_sbom.tenant
  for update;
  if not found then
    raise exception 'no such product version in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  delete from "better_supabase"."sbom_components" z where z."tenant_id" = import_sbom.tenant and z."version_id" = import_sbom.version_id;
  insert into "better_supabase"."sbom_components" ("tenant_id", "version_id", "bom_ref", "component_type", "name", "component_version", "purl", "package_purl", "cpe", "supplier", "licenses", "hashes")
  select import_sbom.tenant, import_sbom.version_id,
    nullif(e ->> 'bomRef', ''), coalesce(nullif(e ->> 'type', ''), 'library'), trim(e ->> 'name'),
    nullif(e ->> 'version', ''), nullif(e ->> 'purl', ''),
    case when nullif(e ->> 'purl', '') is null then null
      else regexp_replace(regexp_replace(e ->> 'purl', '[?#].*$', ''), '@[^@/]*$', '') end,
    nullif(e ->> 'cpe', ''), nullif(e ->> 'supplier', ''),
    case when jsonb_typeof(e -> 'licenses') = 'array' then array(select jsonb_array_elements_text(e -> 'licenses')) else '{}'::text[] end,
    case when jsonb_typeof(e -> 'hashes') = 'array' then e -> 'hashes' else '[]'::jsonb end
  from jsonb_array_elements(import_sbom.components) e;
  get diagnostics v_count = row_count;
  update "better_supabase"."advisory_product_versions" y set
    "sbom_serial" = nullif(import_sbom.serial_number, ''),
    "sbom_spec" = nullif(import_sbom.spec_version, ''),
    "sbom_component_count" = v_count,
    "sbom_imported_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'productId', v_row."product_id", 'version', v_row."version", 'releasedAt', v_row."released_at", 'endOfSupportAt', v_row."end_of_support_at", 'sbomSerial', v_row."sbom_serial", 'sbomSpec', v_row."sbom_spec", 'sbomComponents', v_row."sbom_component_count", 'sbomImportedAt', v_row."sbom_imported_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."import_sbom"(uuid, uuid, jsonb, text, text) from public, anon;
grant execute on function "better_supabase"."import_sbom"(uuid, uuid, jsonb, text, text) to authenticated, service_role;

-- The components of a version by name.
create or replace function "better_supabase"."list_sbom_components"(tenant uuid, version_id uuid, max_count integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sbom_components.tenant is not null and coalesce(better_supabase.can('tenant', list_sbom_components.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'bomRef', t."bom_ref", 'type', t."component_type", 'name', t."name", 'version', t."component_version", 'purl', t."purl", 'cpe', t."cpe", 'supplier', t."supplier", 'licenses', to_jsonb(t."licenses"), 'hashes', t."hashes") order by t."name", t."component_version")
    from (
      select z.* from "better_supabase"."sbom_components" z
      where z."tenant_id" = list_sbom_components.tenant and z."version_id" = list_sbom_components.version_id
      order by z."name", z."component_version"
      limit least(greatest(coalesce(list_sbom_components.max_count, 1000), 1), 5000)
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_sbom_components"(uuid, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_sbom_components"(uuid, uuid, integer) to authenticated, service_role;

-- Registers a vulnerability the organization tracks, or changes what a person
-- entered. A null argument keeps the stored value. cvss_version is 3.0, 3.1 or
-- 4.0; the TypeScript client parses the vector and passes the version and score.
create or replace function "better_supabase"."save_vulnerability"(tenant uuid, vuln_id text, summary text default null, details text default null, aliases text[] default null, cvss_vector text default null, cvss_version text default null, cvss_score numeric default null, affected_purls text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."vulnerabilities";
  v_old "better_supabase"."vulnerabilities";
  v_id text := case when upper(trim(save_vulnerability.vuln_id)) like 'CVE-%' then upper(trim(save_vulnerability.vuln_id)) else trim(save_vulnerability.vuln_id) end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_vulnerability.tenant is not null and coalesce(better_supabase.can('tenant', save_vulnerability.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if coalesce(v_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$' then
    raise exception 'vuln_id must be a CVE, GHSA or other vulnerability id of 3 to 128 characters' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if length(save_vulnerability.summary) > 1000 or length(save_vulnerability.details) > 20000 or length(save_vulnerability.cvss_vector) > 300 then
    raise exception 'summary is at most 1000 characters, details 20000 and the CVSS vector 300' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if save_vulnerability.cvss_version is not null and save_vulnerability.cvss_version not in ('3.0', '3.1', '4.0') then
    raise exception 'cvss_version must be 3.0, 3.1 or 4.0' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if save_vulnerability.cvss_score is not null and save_vulnerability.cvss_score not between 0 and 10 then
    raise exception 'cvss_score must be between 0 and 10' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select * into v_old from "better_supabase"."vulnerabilities" y
  where y."tenant_id" = save_vulnerability.tenant and y."vuln_id" = v_id
  for update;
  if v_old."id" is null then
    insert into "better_supabase"."vulnerabilities" ("tenant_id", "vuln_id", "summary", "details", "aliases", "cvss_vector", "cvss_version", "cvss_score", "severity", "affected_purls")
    values (save_vulnerability.tenant, v_id, nullif(trim(save_vulnerability.summary), ''), nullif(trim(save_vulnerability.details), ''),
      coalesce(save_vulnerability.aliases, '{}'::text[]), save_vulnerability.cvss_vector, save_vulnerability.cvss_version, save_vulnerability.cvss_score,
      (case when save_vulnerability.cvss_score is null then null when save_vulnerability.cvss_score = 0 then 'none' when save_vulnerability.cvss_score < 4 then 'low' when save_vulnerability.cvss_score < 7 then 'medium' when save_vulnerability.cvss_score < 9 then 'high' else 'critical' end), coalesce(save_vulnerability.affected_purls, '{}'::text[]))
    returning * into v_row;
    null;
  else
    update "better_supabase"."vulnerabilities" y set
      "summary" = coalesce(nullif(trim(save_vulnerability.summary), ''), y."summary"),
      "details" = coalesce(nullif(trim(save_vulnerability.details), ''), y."details"),
      "aliases" = coalesce(save_vulnerability.aliases, y."aliases"),
      "cvss_vector" = coalesce(save_vulnerability.cvss_vector, y."cvss_vector"),
      "cvss_version" = coalesce(save_vulnerability.cvss_version, y."cvss_version"),
      "cvss_score" = coalesce(save_vulnerability.cvss_score, y."cvss_score"),
      "severity" = coalesce((case when save_vulnerability.cvss_score is null then null when save_vulnerability.cvss_score = 0 then 'none' when save_vulnerability.cvss_score < 4 then 'low' when save_vulnerability.cvss_score < 7 then 'medium' when save_vulnerability.cvss_score < 9 then 'high' else 'critical' end), y."severity"),
      "affected_purls" = coalesce(save_vulnerability.affected_purls, y."affected_purls"),
      "updated_at" = now()
    where y."id" = v_old."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'vulnId', v_row."vuln_id", 'aliases', to_jsonb(v_row."aliases"), 'summary', v_row."summary", 'details', v_row."details", 'cvssVector', v_row."cvss_vector", 'cvssVersion', v_row."cvss_version", 'cvssScore', v_row."cvss_score", 'severity', v_row."severity", 'epssScore', v_row."epss_score", 'epssPercentile', v_row."epss_percentile", 'epssDate', v_row."epss_date", 'kev', v_row."kev", 'kevAddedOn', v_row."kev_added_on", 'kevDueOn', v_row."kev_due_on", 'kevRansomware', v_row."kev_ransomware", 'affectedPurls', to_jsonb(v_row."affected_purls"), 'references', v_row."reference_links", 'publishedAt', v_row."published_at", 'modifiedAt', v_row."modified_at", 'enrichedAt', v_row."enriched_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_vulnerability"(uuid, text, text, text, text[], text, text, numeric, text[]) from public, anon;
grant execute on function "better_supabase"."save_vulnerability"(uuid, text, text, text, text[], text, text, numeric, text[]) to authenticated, service_role;

-- Stores what the vulnerability feed found for a tracked vulnerability: OSV
-- fields, the EPSS score and the CISA KEV entry. enrichment is { summary,
-- details, aliases, affectedPurls, cvssVector, cvssVersion, cvssScore, severity,
-- publishedAt, modifiedAt, epss: { score, percentile, date }, kev: { addedOn,
-- dueOn, ransomware }, references }. A summary or details a person wrote stay;
-- every other key replaces the stored value when it is present.
create or replace function "better_supabase"."record_vulnerability_enrichment"(tenant uuid, vuln_id text, enrichment jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."vulnerabilities";
  v_old "better_supabase"."vulnerabilities";
  e jsonb := coalesce(record_vulnerability_enrichment.enrichment, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (record_vulnerability_enrichment.tenant is not null and coalesce(better_supabase.can('tenant', record_vulnerability_enrichment.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if jsonb_typeof(e) <> 'object' then
    raise exception 'enrichment must be an object' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select * into v_old from "better_supabase"."vulnerabilities" y
  where y."tenant_id" = record_vulnerability_enrichment.tenant and y."vuln_id" = record_vulnerability_enrichment.vuln_id
  for update;
  if not found then
    raise exception 'no such vulnerability in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  update "better_supabase"."vulnerabilities" y set
    "summary" = coalesce(y."summary", left(nullif(trim(e ->> 'summary'), ''), 1000)),
    "details" = coalesce(y."details", left(nullif(trim(e ->> 'details'), ''), 20000)),
    "aliases" = case when jsonb_typeof(e -> 'aliases') = 'array'
      then (select coalesce(array_agg(distinct a order by a), '{}'::text[]) from unnest(y."aliases" || array(select jsonb_array_elements_text(e -> 'aliases'))) a)
      else y."aliases" end,
    "affected_purls" = case when jsonb_typeof(e -> 'affectedPurls') = 'array'
      then array(select jsonb_array_elements_text(e -> 'affectedPurls'))
      else y."affected_purls" end,
    "cvss_vector" = coalesce(e ->> 'cvssVector', y."cvss_vector"),
    "cvss_version" = coalesce(e ->> 'cvssVersion', y."cvss_version"),
    "cvss_score" = coalesce((e ->> 'cvssScore')::numeric, y."cvss_score"),
    "severity" = coalesce(e ->> 'severity', (case when (e ->> 'cvssScore')::numeric is null then null when (e ->> 'cvssScore')::numeric = 0 then 'none' when (e ->> 'cvssScore')::numeric < 4 then 'low' when (e ->> 'cvssScore')::numeric < 7 then 'medium' when (e ->> 'cvssScore')::numeric < 9 then 'high' else 'critical' end), y."severity"),
    "published_at" = coalesce((e ->> 'publishedAt')::timestamptz, y."published_at"),
    "modified_at" = coalesce((e ->> 'modifiedAt')::timestamptz, y."modified_at"),
    "epss_score" = case when jsonb_typeof(e -> 'epss') = 'object' then (e -> 'epss' ->> 'score')::numeric else y."epss_score" end,
    "epss_percentile" = case when jsonb_typeof(e -> 'epss') = 'object' then (e -> 'epss' ->> 'percentile')::numeric else y."epss_percentile" end,
    "epss_date" = case when jsonb_typeof(e -> 'epss') = 'object' then (e -> 'epss' ->> 'date')::date else y."epss_date" end,
    "kev" = y."kev" or jsonb_typeof(e -> 'kev') = 'object',
    "kev_added_on" = case when jsonb_typeof(e -> 'kev') = 'object' then (e -> 'kev' ->> 'addedOn')::date else y."kev_added_on" end,
    "kev_due_on" = case when jsonb_typeof(e -> 'kev') = 'object' then (e -> 'kev' ->> 'dueOn')::date else y."kev_due_on" end,
    "kev_ransomware" = case when jsonb_typeof(e -> 'kev') = 'object' then coalesce((e -> 'kev' ->> 'ransomware')::boolean, false) else y."kev_ransomware" end,
    "reference_links" = case when jsonb_typeof(e -> 'references') = 'array' then e -> 'references' else y."reference_links" end,
    "enriched_at" = now(),
    "updated_at" = now()
  where y."id" = v_old."id"
  returning * into v_row;
  null;
  if v_row."kev" and not v_old."kev" then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'vulnId', v_row."vuln_id", 'aliases', to_jsonb(v_row."aliases"), 'summary', v_row."summary", 'details', v_row."details", 'cvssVector', v_row."cvss_vector", 'cvssVersion', v_row."cvss_version", 'cvssScore', v_row."cvss_score", 'severity', v_row."severity", 'epssScore', v_row."epss_score", 'epssPercentile', v_row."epss_percentile", 'epssDate', v_row."epss_date", 'kev', v_row."kev", 'kevAddedOn', v_row."kev_added_on", 'kevDueOn', v_row."kev_due_on", 'kevRansomware', v_row."kev_ransomware", 'affectedPurls', to_jsonb(v_row."affected_purls"), 'references', v_row."reference_links", 'publishedAt', v_row."published_at", 'modifiedAt', v_row."modified_at", 'enrichedAt', v_row."enriched_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
  raise exception 'enrichment holds a number or date that doesn''t parse' using errcode = '22023', hint = 'ADVISORY_INVALID';
end;
$$;
revoke execute on function "better_supabase"."record_vulnerability_enrichment"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."record_vulnerability_enrichment"(uuid, text, jsonb) to authenticated, service_role;

-- The vulnerabilities to enrich next, never enriched first: { organizationId,
-- vulnId } rows for a cron. The service role may pass a null tenant to cover
-- every organization. stale_after defaults to one day.
create or replace function "better_supabase"."vulnerabilities_due"(tenant uuid default null, max_count integer default null, stale_after interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (vulnerabilities_due.tenant is not null and coalesce(better_supabase.can('tenant', vulnerabilities_due.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('organizationId', t."tenant_id", 'vulnId', t."vuln_id") order by t."enriched_at" nulls first, t."vuln_id")
    from (
      select y.* from "better_supabase"."vulnerabilities" y
      where (vulnerabilities_due.tenant is null or y."tenant_id" = vulnerabilities_due.tenant)
        and (y."enriched_at" is null or y."enriched_at" < now() - coalesce(vulnerabilities_due.stale_after, interval '1 day'))
      order by y."enriched_at" nulls first, y."vuln_id"
      limit least(greatest(coalesce(vulnerabilities_due.max_count, 25), 1), 500)
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."vulnerabilities_due"(uuid, integer, interval) from public, anon;
grant execute on function "better_supabase"."vulnerabilities_due"(uuid, integer, interval) to authenticated, service_role;

-- The tracked vulnerabilities: exploited ones first, then the likeliest to be
-- exploited (EPSS), then the highest CVSS score.
create or replace function "better_supabase"."list_vulnerabilities"(tenant uuid, kev_only boolean default false, max_count integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_vulnerabilities.tenant is not null and coalesce(better_supabase.can('tenant', list_vulnerabilities.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'vulnId', t."vuln_id", 'aliases', to_jsonb(t."aliases"), 'summary', t."summary", 'details', t."details", 'cvssVector', t."cvss_vector", 'cvssVersion', t."cvss_version", 'cvssScore', t."cvss_score", 'severity', t."severity", 'epssScore', t."epss_score", 'epssPercentile', t."epss_percentile", 'epssDate', t."epss_date", 'kev', t."kev", 'kevAddedOn', t."kev_added_on", 'kevDueOn', t."kev_due_on", 'kevRansomware', t."kev_ransomware", 'affectedPurls', to_jsonb(t."affected_purls"), 'references', t."reference_links", 'publishedAt', t."published_at", 'modifiedAt', t."modified_at", 'enrichedAt', t."enriched_at", 'createdAt', t."created_at", 'updatedAt', t."updated_at") order by t."kev" desc, t."epss_score" desc nulls last, t."cvss_score" desc nulls last, t."vuln_id")
    from (
      select y.* from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = list_vulnerabilities.tenant
        and (not coalesce(list_vulnerabilities.kev_only, false) or y."kev")
      order by y."kev" desc, y."epss_score" desc nulls last, y."cvss_score" desc nulls last, y."vuln_id"
      limit least(greatest(coalesce(list_vulnerabilities.max_count, 200), 1), 1000)
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_vulnerabilities"(uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_vulnerabilities"(uuid, boolean, integer) to authenticated, service_role;

-- The tracked vulnerabilities that match components of a version by package,
-- with the product's VEX status for each. A version without its own statement
-- falls back to the statement for every version. Matching is by package, not by
-- affected version range, so each row is a candidate to triage.
create or replace function "better_supabase"."version_exposure"(tenant uuid, version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (version_exposure.tenant is not null and coalesce(better_supabase.can('tenant', version_exposure.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."advisory_product_versions" y
    where y."id" = version_exposure.version_id and y."tenant_id" = version_exposure.tenant
  ) then
    raise exception 'no such product version in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'vulnerabilityId', t.vulnerability_id, 'vulnId', t.vuln_id, 'severity', t.severity, 'cvssScore', t.cvss_score,
      'epssScore', t.epss_score, 'kev', t.kev, 'componentId', t.component_id, 'componentName', t.component_name,
      'componentVersion', t.component_version, 'purl', t.purl, 'vexStatus', t.vex_status
    ) order by t.kev desc, t.cvss_score desc nulls last, t.vuln_id, t.component_name)
    from (
      select y."id" as vulnerability_id, y."vuln_id" as vuln_id, y."severity" as severity,
        y."cvss_score" as cvss_score, y."epss_score" as epss_score, y."kev" as kev,
        z."id" as component_id, z."name" as component_name, z."component_version" as component_version,
        z."purl" as purl,
        (select w."status" from "better_supabase"."vex_statements" w
          where w."tenant_id" = y."tenant_id" and w."vulnerability_id" = y."id"
            and w."product_id" = ver."product_id"
            and (w."version_id" = ver."id" or w."version_id" is null)
          order by (w."version_id" is null) limit 1) as vex_status
      from "better_supabase"."advisory_product_versions" ver
      join "better_supabase"."sbom_components" z on z."tenant_id" = ver."tenant_id" and z."version_id" = ver."id"
      join "better_supabase"."vulnerabilities" y on y."tenant_id" = ver."tenant_id" and z."package_purl" = any (y."affected_purls")
      where ver."id" = version_exposure.version_id and ver."tenant_id" = version_exposure.tenant
      limit 5000
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."version_exposure"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."version_exposure"(uuid, uuid) to authenticated, service_role;

-- Sets the product's statement for a vulnerability, for one version or, with a
-- null version_id, for every version. not_affected needs a justification; the
-- other statuses take none. affected may carry an action_statement.
create or replace function "better_supabase"."save_vex_statement"(tenant uuid, product_id uuid, vulnerability_id uuid, status text, version_id uuid default null, justification text default null, impact_statement text default null, action_statement text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."vex_statements";
  v_old "better_supabase"."vex_statements";
  v_vuln text;
  v_label text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_vex_statement.tenant is not null and coalesce(better_supabase.can('tenant', save_vex_statement.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if coalesce(save_vex_statement.status, '') not in ('not_affected', 'affected', 'fixed', 'under_investigation') then
    raise exception 'status must be one of not_affected, affected, fixed, under_investigation' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if save_vex_statement.status = 'not_affected' and (save_vex_statement.justification is null and nullif(trim(save_vex_statement.impact_statement), '') is null) then
    raise exception 'not_affected needs a justification or an impact statement' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if save_vex_statement.justification is not null and (save_vex_statement.status <> 'not_affected' or save_vex_statement.justification not in ('component_not_present', 'vulnerable_code_not_present', 'vulnerable_code_not_in_execute_path', 'vulnerable_code_cannot_be_controlled_by_adversary', 'inline_mitigations_already_exist')) then
    raise exception 'a justification applies to not_affected and is one of the OpenVEX justifications' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if length(save_vex_statement.impact_statement) > 5000 or length(save_vex_statement.action_statement) > 5000 then
    raise exception 'impact_statement and action_statement are at most 5000 characters' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."advisory_products" y
    where y."id" = save_vex_statement.product_id and y."tenant_id" = save_vex_statement.tenant
  ) then
    raise exception 'no such product in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  select y."vuln_id" into v_vuln from "better_supabase"."vulnerabilities" y
  where y."id" = save_vex_statement.vulnerability_id and y."tenant_id" = save_vex_statement.tenant;
  if not found then
    raise exception 'no such vulnerability in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  if save_vex_statement.version_id is not null and not exists (
    select 1 from "better_supabase"."advisory_product_versions" y
    where y."id" = save_vex_statement.version_id and y."tenant_id" = save_vex_statement.tenant
      and y."product_id" = save_vex_statement.product_id
  ) then
    raise exception 'no such version of this product in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."vex_statements" w
  where w."tenant_id" = save_vex_statement.tenant and w."product_id" = save_vex_statement.product_id
    and w."vulnerability_id" = save_vex_statement.vulnerability_id
    and w."version_id" is not distinct from save_vex_statement.version_id
  for update;
  if v_old."id" is null then
    insert into "better_supabase"."vex_statements" ("tenant_id", "product_id", "version_id", "vulnerability_id", "status", "justification", "impact_statement", "action_statement", "created_by")
    values (save_vex_statement.tenant, save_vex_statement.product_id, save_vex_statement.version_id, save_vex_statement.vulnerability_id, save_vex_statement.status,
      save_vex_statement.justification, nullif(trim(save_vex_statement.impact_statement), ''), nullif(trim(save_vex_statement.action_statement), ''), (select auth.uid()))
    returning * into v_row;
  else
    update "better_supabase"."vex_statements" w set
      "status" = save_vex_statement.status,
      "justification" = save_vex_statement.justification,
      "impact_statement" = nullif(trim(save_vex_statement.impact_statement), ''),
      "action_statement" = nullif(trim(save_vex_statement.action_statement), ''),
      "updated_at" = now()
    where w."id" = v_old."id"
    returning * into v_row;
  end if;
  null;
  select y."version" into v_label from "better_supabase"."advisory_product_versions" y where y."id" = v_row."version_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'productId', v_row."product_id", 'versionId', v_row."version_id", 'version', v_label, 'vulnerabilityId', v_row."vulnerability_id", 'vulnId', v_vuln, 'status', v_row."status", 'justification', v_row."justification", 'impactStatement', v_row."impact_statement", 'actionStatement', v_row."action_statement", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_vex_statement"(uuid, uuid, uuid, text, uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_vex_statement"(uuid, uuid, uuid, text, uuid, text, text, text) to authenticated, service_role;

-- The product's statements, with the vulnerability id and version they name.
-- With version_id: the ones for that version and for every version.
create or replace function "better_supabase"."list_vex_statements"(tenant uuid, product_id uuid, version_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_vex_statements.tenant is not null and coalesce(better_supabase.can('tenant', list_vex_statements.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', w."id", 'organizationId', w."tenant_id", 'productId', w."product_id", 'versionId', w."version_id", 'version', ver."version", 'vulnerabilityId', w."vulnerability_id", 'vulnId', y."vuln_id", 'status', w."status", 'justification', w."justification", 'impactStatement', w."impact_statement", 'actionStatement', w."action_statement", 'createdBy', w."created_by", 'createdAt', w."created_at", 'updatedAt', w."updated_at") order by y."vuln_id", ver."version" nulls first)
    from "better_supabase"."vex_statements" w
    join "better_supabase"."vulnerabilities" y on y."id" = w."vulnerability_id" and y."tenant_id" = w."tenant_id"
    left join "better_supabase"."advisory_product_versions" ver on ver."id" = w."version_id"
    where w."tenant_id" = list_vex_statements.tenant and w."product_id" = list_vex_statements.product_id
      and (list_vex_statements.version_id is null or w."version_id" is null or w."version_id" = list_vex_statements.version_id)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_vex_statements"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."list_vex_statements"(uuid, uuid, uuid) to authenticated, service_role;

-- Creates a draft advisory about a product and the vulnerabilities it covers,
-- or, with advisory_id, changes one. The tracking id (the CSAF tracking.id,
-- such as ACME-SA-2026-001) can't change after the first publication.
create or replace function "better_supabase"."save_advisory"(tenant uuid, tracking_id text, title text, summary text, product_id uuid, vulnerability_ids uuid[], severity text default null, advisory_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."advisories";
  v_old "better_supabase"."advisories";
  v_ids uuid[] := coalesce(save_advisory.vulnerability_ids, '{}'::uuid[]);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_advisory.tenant is not null and coalesce(better_supabase.can('tenant', save_advisory.tenant, 'advisories.write'), false))) then
    raise exception 'not allowed to change advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if coalesce(save_advisory.tracking_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$' then
    raise exception 'tracking_id must be 3 to 100 letters, digits, dots, dashes and underscores' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if coalesce(length(trim(save_advisory.title)), 0) not between 1 and 300 or length(save_advisory.summary) > 10000 then
    raise exception 'title must be 1 to 300 characters and summary at most 10000' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if save_advisory.severity is not null and save_advisory.severity not in ('none', 'low', 'medium', 'high', 'critical') then
    raise exception 'severity must be one of none, low, medium, high, critical' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if cardinality(v_ids) > 500 then
    raise exception 'an advisory covers at most 500 vulnerabilities' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."advisory_products" y
    where y."id" = save_advisory.product_id and y."tenant_id" = save_advisory.tenant
  ) then
    raise exception 'no such product in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  if (select count(*) from "better_supabase"."vulnerabilities" y where y."tenant_id" = save_advisory.tenant and y."id" = any (v_ids))
    <> (select count(distinct i) from unnest(v_ids) i) then
    raise exception 'no such vulnerability in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  if save_advisory.advisory_id is not null then
    select * into v_old from "better_supabase"."advisories" y
    where y."id" = save_advisory.advisory_id and y."tenant_id" = save_advisory.tenant
    for update;
    if not found then
      raise exception 'no such advisory in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
    end if;
    if v_old."initial_release_at" is not null and v_old."tracking_id" <> save_advisory.tracking_id then
      raise exception 'a published advisory keeps its tracking id' using errcode = '22023', hint = 'ADVISORY_INVALID';
    end if;
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."advisories" ("tenant_id", "tracking_id", "title", "summary", "product_id", "severity", "created_by")
    values (save_advisory.tenant, save_advisory.tracking_id, trim(save_advisory.title), nullif(trim(save_advisory.summary), ''), save_advisory.product_id, save_advisory.severity, (select auth.uid()))
    returning * into v_row;
    null;
  else
    update "better_supabase"."advisories" y set
      "tracking_id" = save_advisory.tracking_id,
      "title" = trim(save_advisory.title),
      "summary" = nullif(trim(save_advisory.summary), ''),
      "product_id" = save_advisory.product_id,
      "severity" = save_advisory.severity,
      "updated_at" = now()
    where y."id" = v_old."id"
    returning * into v_row;
    null;
  end if;
  delete from "better_supabase"."advisory_vulnerabilities" k where k."tenant_id" = v_row."tenant_id" and k."advisory_id" = v_row."id";
  insert into "better_supabase"."advisory_vulnerabilities" ("tenant_id", "advisory_id", "vulnerability_id")
  select v_row."tenant_id", v_row."id", i from (select distinct unnest(v_ids) as i) d;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'trackingId', v_row."tracking_id", 'title', v_row."title", 'summary', v_row."summary", 'productId', v_row."product_id", 'severity', v_row."severity", 'status', v_row."status", 'revision', v_row."revision", 'initialReleaseAt', v_row."initial_release_at", 'currentReleaseAt', v_row."current_release_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('vulnerabilityIds', to_jsonb(array(select distinct unnest(v_ids))));
exception when unique_violation then
  raise exception 'another advisory of this organization has this tracking id' using errcode = '22023', hint = 'ADVISORY_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_advisory"(uuid, text, text, text, uuid, uuid[], text, uuid) from public, anon;
grant execute on function "better_supabase"."save_advisory"(uuid, text, text, text, uuid, uuid[], text, uuid) to authenticated, service_role;

-- Publishes an advisory as interim or final, or publishes a new revision of one
-- already published. The CSAF document version and revision history advance on
-- every call. A final advisory can't go back to interim. Needs
-- advisories.publish.
create or replace function "better_supabase"."publish_advisory"(tenant uuid, advisory_id uuid, status text default 'final', note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."advisories";
  v_old "better_supabase"."advisories";
  v_revision integer;
  v_now timestamptz := now();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (publish_advisory.tenant is not null and coalesce(better_supabase.can('tenant', publish_advisory.tenant, 'advisories.publish'), false))) then
    raise exception 'not allowed to publish advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if coalesce(publish_advisory.status, '') not in ('interim', 'final') then
    raise exception 'status must be interim or final' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if length(publish_advisory.note) > 1000 then
    raise exception 'note is at most 1000 characters' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select * into v_old from "better_supabase"."advisories" y
  where y."id" = publish_advisory.advisory_id and y."tenant_id" = publish_advisory.tenant
  for update;
  if not found then
    raise exception 'no such advisory in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  if v_old."status" = 'final' and publish_advisory.status = 'interim' then
    raise exception 'a final advisory can''t go back to interim' using errcode = '55000', hint = 'ADVISORY_FINAL';
  end if;
  if not exists (select 1 from "better_supabase"."advisory_vulnerabilities" k where k."tenant_id" = v_old."tenant_id" and k."advisory_id" = v_old."id") then
    raise exception 'an advisory needs at least one vulnerability before it is published' using errcode = '55000', hint = 'ADVISORY_EMPTY';
  end if;
  v_revision := v_old."revision" + 1;
  update "better_supabase"."advisories" y set
    "status" = publish_advisory.status,
    "revision" = v_revision,
    "initial_release_at" = coalesce(y."initial_release_at", v_now),
    "current_release_at" = v_now,
    "revision_history" = y."revision_history" || jsonb_build_array(jsonb_build_object(
      'number', v_revision::text,
      'date', to_jsonb(v_now),
      'summary', coalesce(nullif(trim(publish_advisory.note), ''), case when y."initial_release_at" is null then 'Initial release' else 'Revised' end))),
    "updated_at" = v_now
  where y."id" = v_old."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'trackingId', v_row."tracking_id", 'title', v_row."title", 'summary', v_row."summary", 'productId', v_row."product_id", 'severity', v_row."severity", 'status', v_row."status", 'revision', v_row."revision", 'initialReleaseAt', v_row."initial_release_at", 'currentReleaseAt', v_row."current_release_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_advisory"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."publish_advisory"(uuid, uuid, text, text) to authenticated, service_role;

-- The organization's advisories, the newest first, optionally of one status.
create or replace function "better_supabase"."list_advisories"(tenant uuid, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_advisories.tenant is not null and coalesce(better_supabase.can('tenant', list_advisories.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc)
    from "better_supabase"."advisories" y
    where y."tenant_id" = list_advisories.tenant
      and (list_advisories.status is null or y."status" = list_advisories.status)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_advisories"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_advisories"(uuid, text) to authenticated, service_role;

-- One advisory with the ids of the vulnerabilities it covers.
create or replace function "better_supabase"."get_advisory"(tenant uuid, advisory_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."advisories";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (get_advisory.tenant is not null and coalesce(better_supabase.can('tenant', get_advisory.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."advisories" y
  where y."id" = get_advisory.advisory_id and y."tenant_id" = get_advisory.tenant;
  if not found then
    raise exception 'no such advisory in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'trackingId', v_row."tracking_id", 'title', v_row."title", 'summary', v_row."summary", 'productId', v_row."product_id", 'severity', v_row."severity", 'status', v_row."status", 'revision', v_row."revision", 'initialReleaseAt', v_row."initial_release_at", 'currentReleaseAt', v_row."current_release_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'revisionHistory', v_row."revision_history",
    'vulnerabilityIds', coalesce((select jsonb_agg(k."vulnerability_id") from "better_supabase"."advisory_vulnerabilities" k where k."tenant_id" = v_row."tenant_id" and k."advisory_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_advisory"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."get_advisory"(uuid, uuid) to authenticated, service_role;

-- A published advisory with everything a CSAF document needs: the statements,
-- the product versions and the revision history. Service role only, for the
-- public /.well-known/csaf handler.
create or replace function "better_supabase"."get_published_advisory"(tenant uuid, tracking_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."advisories";
begin
  select * into v_row from "better_supabase"."advisories" y
  where y."tenant_id" = get_published_advisory.tenant and y."tracking_id" = get_published_advisory.tracking_id
    and y."initial_release_at" is not null;
  if not found then
    raise exception 'no such published advisory in this organization' using errcode = 'P0002', hint = 'ADVISORY_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'trackingId', v_row."tracking_id", 'title', v_row."title", 'summary', coalesce(v_row."summary", ''),
    'status', v_row."status", 'version', v_row."revision",
    'initialReleaseAt', v_row."initial_release_at", 'currentReleaseAt', v_row."current_release_at",
    'revisionHistory', v_row."revision_history",
    'product', (select jsonb_build_object('key', y."key", 'name', y."name",
      'versions', (select coalesce(jsonb_agg(ver."version" order by ver."created_at", ver."version"), '[]'::jsonb)
        from "better_supabase"."advisory_product_versions" ver where ver."tenant_id" = y."tenant_id" and ver."product_id" = y."id"))
      from "better_supabase"."advisory_products" y where y."id" = v_row."product_id"),
    'vulnerabilities', (select coalesce(jsonb_agg(jsonb_build_object(
        'vulnId', z."vuln_id", 'aliases', to_jsonb(z."aliases"), 'summary', z."summary", 'details', z."details",
        'cvssVector', z."cvss_vector", 'cvssVersion', z."cvss_version", 'cvssScore', z."cvss_score",
        'kevAddedOn', z."kev_added_on",
        'statements', (select coalesce(jsonb_agg(jsonb_build_object(
            'version', ver."version", 'status', w."status", 'justification', w."justification",
            'impactStatement', w."impact_statement", 'actionStatement', w."action_statement"
          ) order by ver."version" nulls first), '[]'::jsonb)
          from "better_supabase"."vex_statements" w left join "better_supabase"."advisory_product_versions" ver on ver."id" = w."version_id"
          where w."vulnerability_id" = z."id" and w."product_id" = v_row."product_id")
      ) order by z."vuln_id"), '[]'::jsonb)
      from "better_supabase"."advisory_vulnerabilities" k join "better_supabase"."vulnerabilities" z on z."id" = k."vulnerability_id"
      where k."advisory_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_published_advisory"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."get_published_advisory"(uuid, text) to service_role;

-- The published advisories for the CSAF index, the newest release first.
create or replace function "better_supabase"."list_published_advisories"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'trackingId', y."tracking_id", 'title', y."title", 'status', y."status", 'version', y."revision",
      'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at"
    ) order by y."current_release_at" desc)
    from "better_supabase"."advisories" y
    where y."tenant_id" = list_published_advisories.tenant and y."initial_release_at" is not null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_published_advisories"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."list_published_advisories"(uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."advisory_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisory_products";
create policy bsb_tenant_scope_select on "better_supabase"."advisory_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisory_products";
create policy bsb_tenant_scope_insert on "better_supabase"."advisory_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisory_products";
create policy bsb_tenant_scope_update on "better_supabase"."advisory_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisory_products";
create policy bsb_tenant_scope_delete on "better_supabase"."advisory_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."advisory_product_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisory_product_versions";
create policy bsb_tenant_scope_select on "better_supabase"."advisory_product_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisory_product_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."advisory_product_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisory_product_versions";
create policy bsb_tenant_scope_update on "better_supabase"."advisory_product_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisory_product_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."advisory_product_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."sbom_components";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."sbom_components";
create policy bsb_tenant_scope_select on "better_supabase"."sbom_components" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."sbom_components";
create policy bsb_tenant_scope_insert on "better_supabase"."sbom_components" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."sbom_components";
create policy bsb_tenant_scope_update on "better_supabase"."sbom_components" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."sbom_components";
create policy bsb_tenant_scope_delete on "better_supabase"."sbom_components" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."vulnerabilities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."vulnerabilities";
create policy bsb_tenant_scope_select on "better_supabase"."vulnerabilities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."vulnerabilities";
create policy bsb_tenant_scope_insert on "better_supabase"."vulnerabilities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."vulnerabilities";
create policy bsb_tenant_scope_update on "better_supabase"."vulnerabilities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."vulnerabilities";
create policy bsb_tenant_scope_delete on "better_supabase"."vulnerabilities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."vex_statements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."vex_statements";
create policy bsb_tenant_scope_select on "better_supabase"."vex_statements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."vex_statements";
create policy bsb_tenant_scope_insert on "better_supabase"."vex_statements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."vex_statements";
create policy bsb_tenant_scope_update on "better_supabase"."vex_statements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."vex_statements";
create policy bsb_tenant_scope_delete on "better_supabase"."vex_statements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."advisories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisories";
create policy bsb_tenant_scope_select on "better_supabase"."advisories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisories";
create policy bsb_tenant_scope_insert on "better_supabase"."advisories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisories";
create policy bsb_tenant_scope_update on "better_supabase"."advisories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisories";
create policy bsb_tenant_scope_delete on "better_supabase"."advisories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."advisory_vulnerabilities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."advisory_vulnerabilities";
create policy bsb_tenant_scope_select on "better_supabase"."advisory_vulnerabilities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('advisories.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."advisory_vulnerabilities";
create policy bsb_tenant_scope_insert on "better_supabase"."advisory_vulnerabilities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."advisory_vulnerabilities";
create policy bsb_tenant_scope_update on "better_supabase"."advisory_vulnerabilities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."advisory_vulnerabilities";
create policy bsb_tenant_scope_delete on "better_supabase"."advisory_vulnerabilities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_172_advisories.sql
-- better-supabase module: advisories
-- @bsb-block-data advisories
-- @bsb-hash sha256:094b7d1f5a897653ebe15e328532177af1785e66afc5a320404d736edb77b705
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('advisories', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
