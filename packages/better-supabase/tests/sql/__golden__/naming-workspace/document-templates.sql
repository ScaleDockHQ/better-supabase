-- ==== schema supabase/schemas/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block document-templates@1 managed
-- @bsb-hash sha256:5e6821f0dee50d463484c06155152b3814826bb1ece7c1db4eb5ac19b1ec83e5
-- Templates for invoices, credit notes, quotes, orders, dunning letters, delivery notes and statements per legal entity and language, reusable text blocks, one versioned variable contract per document type, and render_document, which returns the variables, the chosen template and its texts. An issued invoice or credit note is frozen with the template version it used, so rendering it again never changes it.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_text_blocks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."rendered_documents";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."rendered_documents";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rendered_documents";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."rendered_documents";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rendered_documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Document templates (ADR 0145): per legal entity and language templates, text
-- blocks, one variable contract per document type, render_document and the
-- snapshots that keep an issued document stable.

-- One address in the contract's six keys, from the key names addresses use.
create or replace function "better_supabase"."document_address"(address jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'line1', nullif(btrim(coalesce(a.j ->> 'line1', a.j ->> 'street', a.j ->> 'address1')), ''),
    'line2', nullif(btrim(coalesce(a.j ->> 'line2', a.j ->> 'address2')), ''),
    'postalCode', nullif(btrim(coalesce(a.j ->> 'postalCode', a.j ->> 'postal_code', a.j ->> 'zip')), ''),
    'city', nullif(btrim(a.j ->> 'city'), ''),
    'region', nullif(btrim(coalesce(a.j ->> 'region', a.j ->> 'state')), ''),
    'country', nullif(btrim(a.j ->> 'country'), '')
  )
  from (select case when jsonb_typeof(document_address.address) = 'object' then document_address.address else '{}'::jsonb end as j) a
$$;
revoke execute on function "better_supabase"."document_address"(jsonb) from public, anon;
grant execute on function "better_supabase"."document_address"(jsonb) to authenticated, service_role;

-- The legal entity that issues a document: the given one, else the
-- organization's default. All null when the organization has none.
create or replace function "better_supabase"."document_entity"(tenant uuid, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."legal_entities"%rowtype;
begin
  v_id := "better_supabase"."legal_entity_of"(document_entity.tenant, document_entity.legal_entity);
  if v_id is not null then
    select * into v_row from "better_supabase"."legal_entities" x where x."id" = v_id;
  end if;
  if v_row."id" is null then
    return jsonb_build_object('id', null::text, 'code', null::text, 'name', null::text, 'address', '{"line1":null,"line2":null,"postalCode":null,"city":null,"region":null,"country":null}'::jsonb, 'vatNumber', null::text, 'cocNumber', null::text, 'iban', null::text, 'bic', null::text, 'logoAttachmentId', null::text, 'defaultCurrency', null::text);
  end if;
  return jsonb_build_object('id', v_row."id", 'code', v_row."code", 'name', v_row."name", 'address', "better_supabase"."document_address"(v_row."address"), 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency");
end;
$$;
revoke execute on function "better_supabase"."document_entity"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."document_entity"(uuid, uuid) to authenticated, service_role;

-- The customer of a document. The buyer the document stored comes first, then
-- the company, then the person; address is the fallback address.
create or replace function "better_supabase"."document_party"(tenant uuid, company_id text, contact_id text, buyer jsonb default null, email text default null, address jsonb default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_company record;
  v_person record;
  v_buyer jsonb := case when jsonb_typeof(document_party.buyer) = 'object' then document_party.buyer else '{}'::jsonb end;
  v_company_found boolean := false;
  v_person_found boolean := false;
begin
  
  
  return jsonb_build_object(
    'id', case when v_company_found then document_party.company_id when v_person_found then coalesce(document_party.contact_id, document_party.company_id) else null end,
    'type', case when v_company_found then 'company' when v_person_found then 'person' else null end,
    'name', coalesce(nullif(v_buyer ->> 'name', ''), null::text, null::text),
    'email', coalesce(nullif(v_buyer ->> 'email', ''), null::text, nullif(document_party.email, '')),
    'vatNumber', coalesce(nullif(coalesce(v_buyer ->> 'vatNumber', v_buyer ->> 'vat_number', v_buyer ->> 'vatId'), ''), null::text),
    'language', coalesce(nullif(v_buyer ->> 'language', ''), null::text, null::text),
    'address', "better_supabase"."document_address"(coalesce(case when jsonb_typeof(v_buyer -> 'address') = 'object' then v_buyer -> 'address' end, document_party.address))
  );
end;
$$;
revoke execute on function "better_supabase"."document_party"(uuid, text, text, jsonb, text, jsonb) from public, anon;
grant execute on function "better_supabase"."document_party"(uuid, text, text, jsonb, text, jsonb) to authenticated, service_role;

-- The tax per rate and code of a lines array, counted from the line amounts.
create or replace function "better_supabase"."document_tax_summary"(lines jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'taxRateBps', g.rate,
    'taxCode', g.code,
    'net', g.net::text,
    'tax', round(g.net * g.rate / 10000.0)::bigint::text,
    'gross', (g.net + round(g.net * g.rate / 10000.0)::bigint)::text
  ) order by g.rate, g.code), '[]'::jsonb)
  from (
    select coalesce((l ->> 'taxRateBps')::integer, 0) as rate, l ->> 'taxCode' as code, sum((l ->> 'amount')::bigint) as net
    from jsonb_array_elements(document_tax_summary.lines) l
    group by 1, 2
  ) g
$$;
revoke execute on function "better_supabase"."document_tax_summary"(jsonb) from public, anon;
grant execute on function "better_supabase"."document_tax_summary"(jsonb) to authenticated, service_role;

-- Whether the caller can read the source row of a document.
create or replace function "better_supabase"."document_visible"(tenant uuid, document_type text, document_id uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  return false;
end;
$$;
revoke execute on function "better_supabase"."document_visible"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."document_visible"(uuid, text, uuid) to authenticated, service_role;

-- The variable payload of one document, in the shape of the contract. The
-- caller reads the source rows through row level security. The document
-- language and the template are added by render_document.
create or replace function "better_supabase"."document_variables"(tenant uuid, document_type text, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  case document_variables.document_type
    when 'invoice' then raise exception 'invoice documents need the invoices block' using errcode = '22023', hint = 'DOCUMENT_TYPE_UNAVAILABLE';
    when 'credit_note' then raise exception 'credit note documents need the invoices block' using errcode = '22023', hint = 'DOCUMENT_TYPE_UNAVAILABLE';
    when 'quote' then raise exception 'quote documents need the quotes block' using errcode = '22023', hint = 'DOCUMENT_TYPE_UNAVAILABLE';
    when 'order' then raise exception 'order documents need the orders block' using errcode = '22023', hint = 'DOCUMENT_TYPE_UNAVAILABLE';
    when 'delivery_note' then raise exception 'delivery note documents need the shipments block' using errcode = '22023', hint = 'DOCUMENT_TYPE_UNAVAILABLE';
    when 'dunning_letter' then raise exception 'dunning letter documents need the invoices block' using errcode = '22023', hint = 'DOCUMENT_TYPE_UNAVAILABLE';
    when 'statement' then raise exception 'statement documents need the invoices block' using errcode = '22023', hint = 'DOCUMENT_TYPE_UNAVAILABLE';
    else
      raise exception 'unknown document type' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end case;
end;
$$;
revoke execute on function "better_supabase"."document_variables"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."document_variables"(uuid, text, uuid) to authenticated, service_role;


-- The templates of an organization, per document type, name, legal entity
-- (null for the organization) and language (null for any).
create table if not exists "better_supabase"."document_templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "document_type" text not null check ("document_type" in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement')),
  "language" text check ("language" is null or "language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  "name" text not null default 'default' check ("name" ~ '^[a-z][a-z0-9_-]{0,63}$'),
  "body" text not null check (length(btrim("body")) > 0 and length("body") <= 200000),
  "version" integer not null default 1 check ("version" >= 1),
  "active" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "legal_entity_id") references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict
);
-- One template per slot.
create unique index if not exists "document_templates_slot_idx" on "better_supabase"."document_templates" ("tenant_id", "document_type", "name", coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid), coalesce("language", ''));
create index if not exists "document_templates_lookup_idx" on "better_supabase"."document_templates" ("tenant_id", "document_type", "name") where "active";
create index if not exists "document_templates_entity_idx" on "better_supabase"."document_templates" ("tenant_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_templates_created_by_idx" on "better_supabase"."document_templates" ("created_by") where "created_by" is not null;
alter table "better_supabase"."document_templates" enable row level security;
revoke all on "better_supabase"."document_templates" from public, anon, authenticated;
grant select on "better_supabase"."document_templates" to authenticated;
grant all on "better_supabase"."document_templates" to service_role;
drop policy if exists document_templates_read on "better_supabase"."document_templates";
create policy document_templates_read on "better_supabase"."document_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- Reusable texts, read in a template as texts.<key>.
create table if not exists "better_supabase"."document_text_blocks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,63}$'),
  "language" text check ("language" is null or "language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  "body" text not null check (length(btrim("body")) > 0 and length("body") <= 200000),
  "version" integer not null default 1 check ("version" >= 1),
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "legal_entity_id") references "better_supabase"."legal_entities" ("tenant_id", "id") on delete restrict
);
create unique index if not exists "document_text_blocks_slot_idx" on "better_supabase"."document_text_blocks" ("tenant_id", "key", coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid), coalesce("language", ''));
create index if not exists "document_text_blocks_entity_idx" on "better_supabase"."document_text_blocks" ("tenant_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_text_blocks_created_by_idx" on "better_supabase"."document_text_blocks" ("created_by") where "created_by" is not null;
alter table "better_supabase"."document_text_blocks" enable row level security;
revoke all on "better_supabase"."document_text_blocks" from public, anon, authenticated;
grant select on "better_supabase"."document_text_blocks" to authenticated;
grant all on "better_supabase"."document_text_blocks" to service_role;
drop policy if exists document_text_blocks_read on "better_supabase"."document_text_blocks";
create policy document_text_blocks_read on "better_supabase"."document_text_blocks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- What a document looked like when it was frozen: its variables, the template
-- and the text blocks it used. A snapshot never changes. The template column
-- keeps the body, so deleting or editing the template leaves it as it was.
create table if not exists "better_supabase"."rendered_documents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "document_type" text not null check ("document_type" in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement')),
  "document_id" uuid not null,
  "language" text,
  "legal_entity_id" uuid,
  "contract_version" integer not null,
  "template_id" uuid,
  "template_version" integer,
  "template" jsonb,
  "blocks" jsonb not null default '{}'::jsonb check (jsonb_typeof("blocks") = 'object'),
  "variables" jsonb not null check (jsonb_typeof("variables") = 'object'),
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "document_type", "document_id")
);
create index if not exists "rendered_documents_created_by_idx" on "better_supabase"."rendered_documents" ("created_by") where "created_by" is not null;
alter table "better_supabase"."rendered_documents" enable row level security;
revoke all on "better_supabase"."rendered_documents" from public, anon, authenticated;
grant select on "better_supabase"."rendered_documents" to authenticated;
grant all on "better_supabase"."rendered_documents" to service_role;
-- A snapshot shows to someone who can read the document it froze; a statement
-- has no row of its own, so it shows to the template managers.
drop policy if exists rendered_documents_read on "better_supabase"."rendered_documents";
create policy rendered_documents_read on "better_supabase"."rendered_documents"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("tenant_id", "document_type", "document_id") end));


-- The variable contract of a document type: its version and the paths and
-- types a template can read. Null names every type. A text block reads any of
-- them. The TypeScript type DocumentVariables and the JSON Schema in
-- schemas/document-template-variables-v1.json state the same contract.
create or replace function "better_supabase"."document_template_contract"(document_type text default null)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_all constant jsonb := '{"invoice":{"version":1,"documentType":"invoice","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"credit_note":{"version":1,"documentType":"credit_note","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"},{"path":"document.originalNumber","type":"string"}]},"quote":{"version":1,"documentType":"quote","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.validUntil","type":"date"},{"path":"document.revision","type":"number"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"order":{"version":1,"documentType":"order","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"shipping","type":"object"},{"path":"shipping.address","type":"object"},{"path":"shipping.address.line1","type":"string"},{"path":"shipping.address.line2","type":"string"},{"path":"shipping.address.postalCode","type":"string"},{"path":"shipping.address.city","type":"string"},{"path":"shipping.address.region","type":"string"},{"path":"shipping.address.country","type":"string"},{"path":"shipping.carrier","type":"string"},{"path":"shipping.trackingNumber","type":"string"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"dunning_letter":{"version":1,"documentType":"dunning_letter","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"document.level","type":"number"},{"path":"document.textKey","type":"string"},{"path":"document.asOf","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"delivery_note":{"version":1,"documentType":"delivery_note","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"shipping","type":"object"},{"path":"shipping.address","type":"object"},{"path":"shipping.address.line1","type":"string"},{"path":"shipping.address.line2","type":"string"},{"path":"shipping.address.postalCode","type":"string"},{"path":"shipping.address.city","type":"string"},{"path":"shipping.address.region","type":"string"},{"path":"shipping.address.country","type":"string"},{"path":"shipping.carrier","type":"string"},{"path":"shipping.trackingNumber","type":"string"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"statement":{"version":1,"documentType":"statement","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.asOf","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]}}'::jsonb;
begin
  if document_template_contract.document_type is null then
    return v_all;
  end if;
  if not v_all ? document_template_contract.document_type then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  return v_all -> document_template_contract.document_type;
end;
$$;
revoke execute on function "better_supabase"."document_template_contract"(text) from public, anon;
grant execute on function "better_supabase"."document_template_contract"(text) to authenticated, service_role;

-- The problems of a template body, first to last, as [{ code, message, tag }].
-- Empty when the body is valid. A text block (text_block) may read the
-- variables of any document type and has no texts.<key>. An unknown variable,
-- an unknown filter and a block that is not closed each have a hint code.
create or replace function "better_supabase"."validate_document_template"(document_type text, body text, text_block boolean default false)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_known jsonb := '{}'::jsonb;
  v_contract jsonb;
  v_item jsonb;
  v_parse jsonb := '[]'::jsonb;
  v_check jsonb := '[]'::jsonb;
  v_stack jsonb := '[]'::jsonb;
  v_scope jsonb := '{}'::jsonb;
  v_piece text;
  v_tag text;
  v_match text[];
  v_top jsonb;
  v_path text;
  v_kind text;
  v_head text;
  v_list text;
  v_each text[];
  v_if text[];
  v_value text[];
  v_filter text;
  v_text boolean := not coalesce(validate_document_template.text_block, false);
begin
  if validate_document_template.body is null then
    raise exception 'a template needs a body' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if coalesce(validate_document_template.text_block, false) then
    for v_contract in select c.value from jsonb_each("better_supabase"."document_template_contract"(null)) c loop
      for v_item in select e.value from jsonb_array_elements(v_contract -> 'variables') e loop
        v_known := v_known || jsonb_build_object(v_item ->> 'path', v_item ->> 'type');
      end loop;
    end loop;
  else
    for v_item in select e.value from jsonb_array_elements("better_supabase"."document_template_contract"(validate_document_template.document_type) -> 'variables') e loop
      v_known := v_known || jsonb_build_object(v_item ->> 'path', v_item ->> 'type');
    end loop;
  end if;

  -- Text between the tags holds no brace pair.
  for v_piece in select p from regexp_split_to_table(validate_document_template.body, '\{\{[\s\S]*?\}\}') p loop
    if v_piece ~ '\{\{|\}\}' then
      v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'a brace pair is not closed or not opened', 'tag', btrim(v_piece)));
    end if;
  end loop;

  for v_match in select m from regexp_matches(validate_document_template.body, '\{\{([\s\S]*?)\}\}', 'g') m loop
    v_tag := btrim(v_match[1]);
    v_top := case when jsonb_array_length(v_stack) = 0 then null else v_stack -> (jsonb_array_length(v_stack) - 1) end;

    if v_tag in ('/each', '/if') then
      if v_top is null or v_top ->> 'kind' <> substr(v_tag, 2) then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', v_tag || ' closes nothing', 'tag', v_tag));
      else
        v_stack := v_stack - (jsonb_array_length(v_stack) - 1);
        if v_top ->> 'kind' = 'each' then
          v_scope := v_scope - (v_top ->> 'alias');
        end if;
      end if;
    elsif v_tag = 'else' then
      if v_top is null or v_top ->> 'kind' <> 'if' or (v_top ->> 'else')::boolean then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'else belongs inside one #if', 'tag', v_tag));
      else
        v_stack := jsonb_set(v_stack, array[(jsonb_array_length(v_stack) - 1)::text, 'else'], 'true'::jsonb);
      end if;
    else
      v_each := regexp_match(v_tag, '^#each\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s+as\s+([a-z][A-Za-z0-9_]*)$');
      v_if := regexp_match(v_tag, '^#if\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)$');
      if v_each is not null then
        if coalesce(v_known ->> v_each[1], '') <> 'list' or v_scope ? v_each[1] then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_each[1] || ' is not a list of this document', 'tag', v_each[1]));
        end if;
        if v_known ? v_each[2] or v_scope ? v_each[2] then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', v_each[2] || ' is already a variable', 'tag', v_each[2]));
        end if;
        v_stack := v_stack || jsonb_build_array(jsonb_build_object('kind', 'each', 'alias', v_each[2], 'else', false));
        v_scope := v_scope || jsonb_build_object(v_each[2], v_each[1]);
      elsif v_if is not null then
        v_path := v_if[1];
        v_kind := null;
        v_head := split_part(v_path, '.', 1);
        if v_scope ? v_head then
          v_kind := case when position('.' in v_path) = 0 then null else v_known ->> ((v_scope ->> v_head) || '[]' || substr(v_path, length(v_head) + 1)) end;
        elsif v_path ~ '^texts\.[a-z][a-z0-9_]{0,63}$' then
          v_kind := case when v_text then 'string' else null end;
        else
          v_kind := v_known ->> v_path;
        end if;
        if v_kind is null then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a variable of this document', 'tag', v_path));
        end if;
        v_stack := v_stack || jsonb_build_array(jsonb_build_object('kind', 'if', 'else', false));
      elsif left(v_tag, 1) in ('#', '/') then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'unknown block tag', 'tag', v_tag));
      else
        v_value := regexp_match(v_tag, '^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)(?:\s*\|\s*([A-Za-z_]+))?$');
        if v_value is null then
          v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'a placeholder is a path with an optional filter', 'tag', v_tag));
        else
          v_filter := v_value[2];
          if v_filter is not null and v_filter not in ('money', 'date') then
            v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER', 'message', 'unknown filter ' || v_filter || '; use money or date', 'tag', v_tag));
          else
            v_path := v_value[1];
            v_kind := null;
            v_head := split_part(v_path, '.', 1);
            if v_scope ? v_head then
              v_kind := case when position('.' in v_path) = 0 then null else v_known ->> ((v_scope ->> v_head) || '[]' || substr(v_path, length(v_head) + 1)) end;
            elsif v_path ~ '^texts\.[a-z][a-z0-9_]{0,63}$' then
              v_kind := case when v_text then 'string' else null end;
            else
              v_kind := v_known ->> v_path;
            end if;
            if v_kind is null then
              v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a variable of this document', 'tag', v_path));
            elsif v_kind in ('object', 'list') then
              v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a single value', 'tag', v_path));
            end if;
          end if;
        end if;
      end if;
    end if;
  end loop;

  for v_item in select s.value from jsonb_array_elements(v_stack) s loop
    v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', '#' || (v_item ->> 'kind') || ' is not closed', 'tag', '#' || (v_item ->> 'kind')));
  end loop;

  return v_parse || v_check;
end;
$$;
revoke execute on function "better_supabase"."validate_document_template"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."validate_document_template"(text, text, boolean) to authenticated, service_role;

-- Raises with the hint code of the first problem of a template body.
create or replace function "better_supabase"."assert_document_template"(document_type text, body text, text_block boolean default false)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_issues jsonb;
  v_code text;
  v_message text;
begin
  v_issues := "better_supabase"."validate_document_template"(assert_document_template.document_type, assert_document_template.body, assert_document_template.text_block);
  if jsonb_array_length(v_issues) = 0 then
    return;
  end if;
  v_code := v_issues -> 0 ->> 'code';
  v_message := v_issues -> 0 ->> 'message';
  if v_code = 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE' then
    raise exception '%', v_message using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE';
  elsif v_code = 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER' then
    raise exception '%', v_message using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER';
  end if;
  raise exception '%', v_message using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_SYNTAX';
end;
$$;
revoke execute on function "better_supabase"."assert_document_template"(text, text, boolean) from public, anon, authenticated;

-- How well a template or text block fits a request, lower first: its own
-- entity before the organization's, and inside each its exact language, its
-- base language (nl for nl-nl), then no language, then any other language.
create or replace function "better_supabase"."document_slot_rank"(entity uuid, wanted_entity uuid, language text, wanted_language text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when document_slot_rank.entity is not distinct from document_slot_rank.wanted_entity and document_slot_rank.entity is not null then 0 else 3 end
    + case
      when document_slot_rank.wanted_language is not null and document_slot_rank.language = document_slot_rank.wanted_language then 0
      when document_slot_rank.wanted_language is not null and document_slot_rank.language = split_part(document_slot_rank.wanted_language, '-', 1) then 1
      when document_slot_rank.language is null then 2
      else 6
    end
$$;
revoke execute on function "better_supabase"."document_slot_rank"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."document_slot_rank"(uuid, uuid, text, text) to authenticated, service_role;

-- Saves the template of a slot: a document type, a name, a legal entity (null
-- for the organization) and a language (null for any). Saving a changed body
-- raises the version by one; the same body and state change nothing. Raises
-- with a hint code when the body names an unknown variable.
create or replace function "better_supabase"."save_document_template"(tenant uuid, document_type text, body text, language text default null, name text default 'default', legal_entity_id uuid default null, active boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."document_templates"%rowtype;
  v_language text := lower(nullif(btrim(save_document_template.language), ''));
  v_name text := coalesce(nullif(btrim(save_document_template.name), ''), 'default');
  v_active boolean := coalesce(save_document_template.active, true);
  v_changed boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_document_template.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if save_document_template.document_type is null or save_document_template.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  if v_name !~ '^[a-z][a-z0-9_-]{0,63}$' then
    raise exception 'a template name is lower case letters, digits, _ and -, from a letter, up to 64 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a language is a code such as nl or nl-NL' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_template.body is null or length(btrim(save_document_template.body)) = 0 or length(save_document_template.body) > 200000 then
    raise exception 'a template body is 1 to 200000 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_template.legal_entity_id is not null then
    perform "better_supabase"."legal_entity_of"(save_document_template.tenant, save_document_template.legal_entity_id);
  end if;
  perform "better_supabase"."assert_document_template"(save_document_template.document_type, save_document_template.body);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_template_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_document_template.tenant, save_document_template.document_type;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('document_templates:' || save_document_template.tenant::text, 0));
  select * into v_row from "better_supabase"."document_templates" t
    where t."tenant_id" = save_document_template.tenant
      and t."document_type" = save_document_template.document_type
      and t."name" = v_name
      and t."legal_entity_id" is not distinct from save_document_template.legal_entity_id
      and t."language" is not distinct from v_language;
  if found then
    v_changed := v_row."body" <> save_document_template.body;
    if not v_changed and v_row."active" = v_active then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    update "better_supabase"."document_templates" t set
      "body" = save_document_template.body,
      "version" = t."version" + case when v_changed then 1 else 0 end,
      "active" = v_active,
      "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    null;
  else
    insert into "better_supabase"."document_templates" ("tenant_id", "legal_entity_id", "document_type", "language", "name", "body", "active")
    values (save_document_template.tenant, save_document_template.legal_entity_id, save_document_template.document_type, v_language, v_name, save_document_template.body, v_active)
    returning * into v_row;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_document_template"(uuid, text, text, text, text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."save_document_template"(uuid, text, text, text, text, uuid, boolean) to authenticated, service_role;

-- Turns a template on or off. An inactive template drops out of the fallback
-- chain; documents already frozen keep the copy they froze.
create or replace function "better_supabase"."set_document_template_active"(template_id uuid, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."document_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."document_templates" t where t."id" = set_document_template_active.template_id;
  if not found then
    raise exception 'document template not found' using errcode = 'P0002', hint = 'DOCUMENT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if v_row."active" is distinct from coalesce(set_document_template_active.active, true) then
    update "better_supabase"."document_templates" t set "active" = coalesce(set_document_template_active.active, true), "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_document_template_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_document_template_active"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."get_document_template"(template_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."document_templates"%rowtype;
begin
  select * into v_row from "better_supabase"."document_templates" t where t."id" = get_document_template.template_id;
  if not found then
    raise exception 'document template not found' using errcode = 'P0002', hint = 'DOCUMENT_TEMPLATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_document_template"(uuid) from public, anon;
grant execute on function "better_supabase"."get_document_template"(uuid) to authenticated, service_role;

-- The templates of an organization by document type, name, entity (the
-- organization's first) and language.
create or replace function "better_supabase"."list_document_templates"(tenant uuid, document_type text default null, legal_entity_id uuid default null, active_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") order by t."document_type", t."name", t."legal_entity_id" nulls first, t."language" nulls first), '[]'::jsonb)
  from "better_supabase"."document_templates" t
  where t."tenant_id" = list_document_templates.tenant
    and (list_document_templates.document_type is null or t."document_type" = list_document_templates.document_type)
    and (list_document_templates.legal_entity_id is null or t."legal_entity_id" = list_document_templates.legal_entity_id)
    and (not coalesce(list_document_templates.active_only, false) or t."active")
$$;
revoke execute on function "better_supabase"."list_document_templates"(uuid, text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_document_templates"(uuid, text, uuid, boolean) to authenticated, service_role;

-- Saves a reusable text, read in a template as texts.<key>: a payment terms
-- sentence, a dunning text, a footer, a legal line. The text may hold the same
-- placeholders a template does, of any document type. An entity text beats the
-- organization's, and an exact language beats a text with no language.
create or replace function "better_supabase"."save_document_text_block"(tenant uuid, key text, body text, language text default null, legal_entity_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."document_text_blocks"%rowtype;
  v_language text := lower(nullif(btrim(save_document_text_block.language), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_document_text_block.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if save_document_text_block.key is null or save_document_text_block.key !~ '^[a-z][a-z0-9_]{0,63}$' then
    raise exception 'a text key is lower case letters, digits and _, from a letter, up to 64 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a language is a code such as nl or nl-NL' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_text_block.body is null or length(btrim(save_document_text_block.body)) = 0 or length(save_document_text_block.body) > 200000 then
    raise exception 'a text block body is 1 to 200000 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_text_block.legal_entity_id is not null then
    perform "better_supabase"."legal_entity_of"(save_document_text_block.tenant, save_document_text_block.legal_entity_id);
  end if;
  perform "better_supabase"."assert_document_template"(null, save_document_text_block.body, true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_text_block_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_document_text_block.tenant, save_document_text_block.key;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('document_text_blocks:' || save_document_text_block.tenant::text, 0));
  select * into v_row from "better_supabase"."document_text_blocks" b
    where b."tenant_id" = save_document_text_block.tenant
      and b."key" = save_document_text_block.key
      and b."legal_entity_id" is not distinct from save_document_text_block.legal_entity_id
      and b."language" is not distinct from v_language;
  if found then
    if v_row."body" = save_document_text_block.body then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'key', v_row."key", 'language', v_row."language", 'body', v_row."body", 'version', v_row."version", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    update "better_supabase"."document_text_blocks" b set "body" = save_document_text_block.body, "version" = b."version" + 1, "updated_at" = now()
    where b."id" = v_row."id"
    returning * into v_row;
    null;
  else
    insert into "better_supabase"."document_text_blocks" ("tenant_id", "legal_entity_id", "key", "language", "body")
    values (save_document_text_block.tenant, save_document_text_block.legal_entity_id, save_document_text_block.key, v_language, save_document_text_block.body)
    returning * into v_row;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_text_block_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'key', v_row."key", 'language', v_row."language", 'body', v_row."body", 'version', v_row."version", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_document_text_block"(uuid, text, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_document_text_block"(uuid, text, text, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_document_text_blocks"(tenant uuid, key text default null, legal_entity_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', b."id", 'organizationId', b."tenant_id", 'legalEntityId', b."legal_entity_id", 'key', b."key", 'language', b."language", 'body', b."body", 'version', b."version", 'createdAt', b."created_at", 'updatedAt', b."updated_at") order by b."key", b."legal_entity_id" nulls first, b."language" nulls first), '[]'::jsonb)
  from "better_supabase"."document_text_blocks" b
  where b."tenant_id" = list_document_text_blocks.tenant
    and (list_document_text_blocks.key is null or b."key" = list_document_text_blocks.key)
    and (list_document_text_blocks.legal_entity_id is null or b."legal_entity_id" = list_document_text_blocks.legal_entity_id)
$$;
revoke execute on function "better_supabase"."list_document_text_blocks"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_document_text_blocks"(uuid, text, uuid) to authenticated, service_role;

-- The template a document gets: the legal entity's template in the document's
-- language, the entity's template for any language, the organization's in the
-- language, then the organization's for any language. Legal entity null means
-- the default entity. A language also matches by its base (nl for nl-nl), and a
-- template in another language is the last resort. Null when nothing fits.
create or replace function "better_supabase"."resolve_document_template"(tenant uuid, document_type text, legal_entity_id uuid default null, language text default null, name text default 'default')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entity uuid;
  v_language text := lower(nullif(btrim(resolve_document_template.language), ''));
  v_row "better_supabase"."document_templates"%rowtype;
  v_rank integer;
begin
  v_entity := "better_supabase"."legal_entity_of"(resolve_document_template.tenant, resolve_document_template.legal_entity_id);
  select * into v_row
  from "better_supabase"."document_templates" t
  where t."tenant_id" = resolve_document_template.tenant
    and t."document_type" = resolve_document_template.document_type
    and t."name" = coalesce(resolve_document_template.name, 'default')
    and t."active"
    and (t."legal_entity_id" is null or t."legal_entity_id" = v_entity)
  order by "better_supabase"."document_slot_rank"(t."legal_entity_id", v_entity, t."language", v_language), t."updated_at" desc
  limit 1;
  if not found then
    return null;
  end if;
  v_rank := "better_supabase"."document_slot_rank"(v_row."legal_entity_id", v_entity, v_row."language", v_language);
  return jsonb_build_object(
    'id', v_row."id",
    'name', v_row."name",
    'documentType', v_row."document_type",
    'legalEntityId', v_row."legal_entity_id",
    'language', v_row."language",
    'version', v_row."version",
    'body', v_row."body",
    'source', case v_rank
      when 0 then 'entity_language'
      when 1 then 'entity_language'
      when 2 then 'entity'
      when 3 then 'organization_language'
      when 4 then 'organization_language'
      when 5 then 'organization'
      when 6 then 'entity_other_language'
      else 'organization_other_language' end
  );
end;
$$;
revoke execute on function "better_supabase"."resolve_document_template"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."resolve_document_template"(uuid, text, uuid, text, text) to authenticated, service_role;

-- The text blocks for these keys, as an object of key to body, each chosen by
-- the same chain as a template. A key with no block is left out.
create or replace function "better_supabase"."resolve_document_blocks"(tenant uuid, keys text[], legal_entity_id uuid default null, language text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entity uuid;
  v_language text := lower(nullif(btrim(resolve_document_blocks.language), ''));
  v_result jsonb;
begin
  v_entity := "better_supabase"."legal_entity_of"(resolve_document_blocks.tenant, resolve_document_blocks.legal_entity_id);
  select coalesce(jsonb_object_agg(f.key, f.body), '{}'::jsonb) into v_result
  from (
    select distinct on (b."key") b."key" as key, b."body" as body
    from "better_supabase"."document_text_blocks" b
    where b."tenant_id" = resolve_document_blocks.tenant
      and b."key" = any (coalesce(resolve_document_blocks.keys, '{}'::text[]))
      and (b."legal_entity_id" is null or b."legal_entity_id" = v_entity)
    order by b."key", "better_supabase"."document_slot_rank"(b."legal_entity_id", v_entity, b."language", v_language), b."updated_at" desc
  ) f;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."resolve_document_blocks"(uuid, text[], uuid, text) from public, anon;
grant execute on function "better_supabase"."resolve_document_blocks"(uuid, text[], uuid, text) to authenticated, service_role;

-- The variables, the chosen template and its text blocks for a document as it
-- stands now. The language is the one asked for, else the buyer's.
create or replace function "better_supabase"."document_render_live"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_vars jsonb;
  v_entity uuid;
  v_language text;
  v_template jsonb;
  v_keys text[] := '{}'::text[];
  v_text_key text;
  v_blocks jsonb := '{}'::jsonb;
begin
  v_language := lower(nullif(btrim(document_render_live.language), ''));
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a language is a code such as nl or nl-NL' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  v_vars := "better_supabase"."document_variables"(document_render_live.tenant, document_render_live.document_type, document_render_live.document_id);
  v_entity := nullif(v_vars #>> '{entity,id}', '')::uuid;
  v_language := coalesce(v_language, lower(nullif(btrim(v_vars #>> '{buyer,language}'), '')));
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    v_language := null;
  end if;
  v_template := "better_supabase"."resolve_document_template"(document_render_live.tenant, document_render_live.document_type, v_entity, v_language, coalesce(document_render_live.template_name, 'default'));
  if v_template is not null then
    select coalesce(array_agg(distinct m[1]), '{}'::text[]) into v_keys
    from regexp_matches(v_template ->> 'body', 'texts\.([a-z][a-z0-9_]{0,63})', 'g') m;
    v_text_key := nullif(v_vars #>> '{document,textKey}', '');
    if v_text_key is not null and v_text_key ~ '^[a-z][a-z0-9_]{0,63}$' and not v_text_key = any (v_keys) then
      v_keys := v_keys || v_text_key;
    end if;
    v_blocks := "better_supabase"."resolve_document_blocks"(document_render_live.tenant, v_keys, v_entity, v_language);
    if v_text_key is not null and v_blocks ? v_text_key then
      v_blocks := v_blocks || jsonb_build_object('dunning', v_blocks -> v_text_key);
    end if;
  end if;
  v_vars := jsonb_set(v_vars, '{document,language}', coalesce(to_jsonb(v_language), 'null'::jsonb));
  return jsonb_build_object(
    'contractVersion', 1,
    'documentType', document_render_live.document_type,
    'documentId', document_render_live.document_id,
    'legalEntityId', v_entity,
    'language', v_language,
    'variables', v_vars,
    'template', v_template,
    'blocks', v_blocks,
    'frozen', false,
    'frozenAt', null,
    'snapshotId', null
  );
end;
$$;
revoke execute on function "better_supabase"."document_render_live"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."document_render_live"(uuid, text, uuid, text, text) to authenticated, service_role;

-- Everything a renderer needs for one document: the variable payload, the
-- chosen template and the text blocks it reads. A document that was frozen
-- (an issued invoice or credit note, or after freeze_document) returns the
-- copy it froze, so editing a template later never changes it; fresh = true
-- renders the document as it stands now with today's templates instead.
create or replace function "better_supabase"."render_document"(tenant uuid, document_type text, document_id uuid, language text default null, fresh boolean default false, template_name text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."rendered_documents"%rowtype;
begin
  if render_document.document_type is null or render_document.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  if not coalesce(render_document.fresh, false) then
    select * into v_row from "better_supabase"."rendered_documents" s
      where s."tenant_id" = render_document.tenant
        and s."document_type" = render_document.document_type
        and s."document_id" = render_document.document_id;
    if found then
      return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
    end if;
  end if;
  return "better_supabase"."document_render_live"(render_document.tenant, render_document.document_type, render_document.document_id, render_document.language, render_document.template_name);
end;
$$;
revoke execute on function "better_supabase"."render_document"(uuid, text, uuid, text, boolean, text) from public, anon;
grant execute on function "better_supabase"."render_document"(uuid, text, uuid, text, boolean, text) to authenticated, service_role;

-- Freezes a document: stores the variables, the template and the text blocks
-- as they are now. A frozen document returns its snapshot unchanged.
create or replace function "better_supabase"."document_freeze"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."rendered_documents"%rowtype;
  v_live jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('rendered_documents:' || document_freeze.tenant::text || ':' || document_freeze.document_id::text, 0));
  select * into v_row from "better_supabase"."rendered_documents" s
    where s."tenant_id" = document_freeze.tenant
      and s."document_type" = document_freeze.document_type
      and s."document_id" = document_freeze.document_id;
  if found then
    return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
  end if;
  v_live := "better_supabase"."document_render_live"(document_freeze.tenant, document_freeze.document_type, document_freeze.document_id, document_freeze.language, document_freeze.template_name);
  insert into "better_supabase"."rendered_documents" ("tenant_id", "document_type", "document_id", "language", "legal_entity_id", "contract_version", "template_id", "template_version", "template", "blocks", "variables")
  values (
    document_freeze.tenant, document_freeze.document_type, document_freeze.document_id,
    v_live ->> 'language', nullif(v_live ->> 'legalEntityId', '')::uuid, (v_live ->> 'contractVersion')::integer,
    nullif(v_live #>> '{template,id}', '')::uuid, nullif(v_live #>> '{template,version}', '')::integer,
    v_live -> 'template', v_live -> 'blocks', v_live -> 'variables')
  returning * into v_row;
  null;
  return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
end;
$$;
revoke execute on function "better_supabase"."document_freeze"(uuid, text, uuid, text, text) from public, anon, authenticated;

-- Freezes a document on request. An invoice and a credit note freeze when they
-- are issued; call this for the other documents when you send them.
create or replace function "better_supabase"."freeze_document"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', freeze_document.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if freeze_document.document_type is null or freeze_document.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  return "better_supabase"."document_freeze"(freeze_document.tenant, freeze_document.document_type, freeze_document.document_id, freeze_document.language, freeze_document.template_name);
end;
$$;
revoke execute on function "better_supabase"."freeze_document"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."freeze_document"(uuid, text, uuid, text, text) to authenticated, service_role;

-- A snapshot never changes; to freeze again, delete it first.
create or replace function "better_supabase"."document_snapshot_immutable"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a frozen document never changes' using errcode = '23000', hint = 'DOCUMENT_SNAPSHOT_IMMUTABLE';
end;
$$;
revoke execute on function "better_supabase"."document_snapshot_immutable"() from public, anon, authenticated;
drop trigger if exists bsb_frozen_render_guard on "better_supabase"."rendered_documents";
create trigger bsb_frozen_render_guard
  before update on "better_supabase"."rendered_documents"
  for each row execute function "better_supabase"."document_snapshot_immutable"();


-- item.data is { documentType, body, name?, language?, legalEntityId? or
-- legalEntity? (a code), active? }. The slot is the document type, name, legal
-- entity and language; importing it again changes the body and raises the version.
create or replace function "better_supabase"."import_document_template"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_document_template.item ->> 'tenant')::uuid;
  v_data jsonb := import_document_template.item -> 'data';
  v_entity uuid;
  v_saved jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a template item is an object' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if nullif(v_data ->> 'legalEntityId', '') is not null then
    v_entity := (v_data ->> 'legalEntityId')::uuid;
  elsif nullif(v_data ->> 'legalEntity', '') is not null then
    select x."id" into v_entity from "better_supabase"."legal_entities" x
      where x."tenant_id" = v_tenant and x."code" = v_data ->> 'legalEntity';
    if v_entity is null then
      raise exception 'the legal entity code is unknown' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  v_saved := "better_supabase"."save_document_template"(v_tenant, v_data ->> 'documentType', v_data ->> 'body', v_data ->> 'language',
    coalesce(nullif(v_data ->> 'name', ''), 'default'), v_entity, coalesce((v_data ->> 'active')::boolean, true));
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_document_template"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_document_template"(uuid, jsonb, text) to service_role;

-- item.data is { key, body, language?, legalEntityId? or legalEntity? }.
create or replace function "better_supabase"."import_document_text_block"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_document_text_block.item ->> 'tenant')::uuid;
  v_data jsonb := import_document_text_block.item -> 'data';
  v_entity uuid;
  v_saved jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a text block item is an object' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if nullif(v_data ->> 'legalEntityId', '') is not null then
    v_entity := (v_data ->> 'legalEntityId')::uuid;
  elsif nullif(v_data ->> 'legalEntity', '') is not null then
    select x."id" into v_entity from "better_supabase"."legal_entities" x
      where x."tenant_id" = v_tenant and x."code" = v_data ->> 'legalEntity';
    if v_entity is null then
      raise exception 'the legal entity code is unknown' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  v_saved := "better_supabase"."save_document_text_block"(v_tenant, v_data ->> 'key', v_data ->> 'body', v_data ->> 'language', v_entity);
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_document_text_block"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_document_text_block"(uuid, jsonb, text) to service_role;

-- When a template or text block last changed, for the conflict check of imports.
create or replace function "better_supabase"."document_template_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select t."updated_at" from "better_supabase"."document_templates" t where t."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."document_template_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."document_template_updated_at"(text) to service_role;

create or replace function "better_supabase"."document_text_block_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select b."updated_at" from "better_supabase"."document_text_blocks" b where b."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."document_text_block_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."document_text_block_updated_at"(text) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."document_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_templates";
create policy bsb_tenant_scope_select on "better_supabase"."document_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."document_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_templates";
create policy bsb_tenant_scope_update on "better_supabase"."document_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."document_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."document_text_blocks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_select on "better_supabase"."document_text_blocks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_insert on "better_supabase"."document_text_blocks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_update on "better_supabase"."document_text_blocks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_delete on "better_supabase"."document_text_blocks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rendered_documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_select on "better_supabase"."rendered_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("tenant_id", "document_type", "document_id") end))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_insert on "better_supabase"."rendered_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_update on "better_supabase"."rendered_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_delete on "better_supabase"."rendered_documents" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block-data document-templates
-- @bsb-hash sha256:78c1630b141d582941b9c29d483d8b522b90759b462aa33a62301aff19a8ff53
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('document-templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
