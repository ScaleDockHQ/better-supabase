-- ==== alone: schema supabase/schemas/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block document-templates@1 managed
-- @bsb-hash sha256:e5cffab85f821ebd59fd36d7e84995b2f2bba89a0839c34b611135a0e4ba7e05
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
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."document_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_templates";
create policy bsb_tenant_scope_update on "better_supabase"."document_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."document_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."document_text_blocks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_select on "better_supabase"."document_text_blocks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_insert on "better_supabase"."document_text_blocks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_update on "better_supabase"."document_text_blocks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_delete on "better_supabase"."document_text_blocks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rendered_documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_select on "better_supabase"."rendered_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("tenant_id", "document_type", "document_id") end))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_insert on "better_supabase"."rendered_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_update on "better_supabase"."rendered_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_delete on "better_supabase"."rendered_documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_163_document_templates.sql
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

-- ==== with every module: schema supabase/schemas/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block document-templates@1 managed
-- @bsb-hash sha256:3dcf531ad0151d5e91595da3d1d34b750cedb3bc98e5d5ef42393cf1554d3539
-- Templates for invoices, credit notes, quotes, orders, dunning letters, delivery notes and statements per legal entity and language, reusable text blocks, one versioned variable contract per document type, and render_document, which returns the variables, the chosen template and its texts. An issued invoice or credit note is frozen with the template version it used, so rendering it again never changes it.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
  v_company "better_supabase"."companies"%rowtype;
  v_person "better_supabase"."people"%rowtype;
  v_buyer jsonb := case when jsonb_typeof(document_party.buyer) = 'object' then document_party.buyer else '{}'::jsonb end;
  v_company_found boolean := false;
  v_person_found boolean := false;
begin
  select * into v_company from "better_supabase"."companies" x where x."id"::text = document_party.company_id and x."tenant_id" = document_party.tenant;
  v_company_found := found;
  select * into v_person from "better_supabase"."people" x where x."id"::text = coalesce(document_party.contact_id, document_party.company_id) and x."tenant_id" = document_party.tenant;
  v_person_found := found;
  return jsonb_build_object(
    'id', case when v_company_found then document_party.company_id when v_person_found then coalesce(document_party.contact_id, document_party.company_id) else null end,
    'type', case when v_company_found then 'company' when v_person_found then 'person' else null end,
    'name', coalesce(nullif(v_buyer ->> 'name', ''), case when v_company_found then v_company."name"::text end, case when v_person_found then v_person."name"::text end),
    'email', coalesce(nullif(v_buyer ->> 'email', ''), case when v_person_found then v_person."email"::text end, nullif(document_party.email, '')),
    'vatNumber', coalesce(nullif(coalesce(v_buyer ->> 'vatNumber', v_buyer ->> 'vat_number', v_buyer ->> 'vatId'), ''), case when v_company_found then v_company."vat_id"::text end),
    'language', coalesce(nullif(v_buyer ->> 'language', ''), case when v_company_found then v_company."language"::text end, case when v_person_found then v_person."language"::text end),
    'address', "better_supabase"."document_address"(coalesce(case when jsonb_typeof(v_buyer -> 'address') = 'object' then v_buyer -> 'address' end, case when v_company_found then v_company."address" end, document_party.address))
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
  case document_visible.document_type
    when 'invoice', 'credit_note' then
      return exists (select 1 from "better_supabase"."invoices" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'quote' then
      return exists (select 1 from "better_supabase"."quotes" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'order' then
      return exists (select 1 from "better_supabase"."orders" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'delivery_note' then
      return exists (select 1 from "better_supabase"."shipments" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'dunning_letter' then
      return exists (select 1 from "better_supabase"."invoice_dunning_run_items" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    else
      return false;
  end case;
end;
$$;
revoke execute on function "better_supabase"."document_visible"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."document_visible"(uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."document_variables_invoice"(tenant uuid, document_id uuid, credit_note boolean)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."invoices"%rowtype;
  v_lines jsonb;
begin
  select * into v_row from "better_supabase"."invoices" x
    where x."id" = document_variables_invoice.document_id and x."tenant_id" = document_variables_invoice.tenant;
  if not found or v_row."kind" = 'credit_note' is distinct from document_variables_invoice.credit_note then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_lines := (select coalesce(jsonb_agg(jsonb_build_object(
      'position', l.n,
      'description', l."description",
      'sku', null::text,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', trim_scale((l."quantity")::numeric)::text,
      'unitAmount', (l."unit_amount")::bigint::text,
      'discountBps', l."discount_bps",
      'discountAmount', (l."discount_amount")::bigint::text,
      'taxRateBps', l."tax_rate_bps",
      'taxCode', l."tax_code",
      'amount', (round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0))))::bigint::text
    ) order by l.n), '[]'::jsonb)
      from (
        select x.*, row_number() over (order by x."position", x."id") as n
        from "better_supabase"."invoice_lines" x
        where x."parent_id" = v_row."id"
      ) l
      where true);
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', case when document_variables_invoice.credit_note then 'credit_note' else 'invoice' end, 'number', coalesce(v_row."identifier", v_row."number"::text), 'title', v_row."title", 'status', v_row."status"::text, 'date', to_char(v_row."issued_on", 'YYYY-MM-DD'), 'currency', trim(v_row."currency"), 'language', null::text, 'note', v_row."note", 'reference', null::text, 'dueOn', to_char(v_row."due_on", 'YYYY-MM-DD'), 'originalNumber', case when document_variables_invoice.credit_note then (select coalesce(o."identifier", o."number"::text) from "better_supabase"."invoices" o where o."id" = v_row."original_id") end),
    'entity', "better_supabase"."document_entity"(document_variables_invoice.tenant, null::uuid),
    'buyer', "better_supabase"."document_party"(document_variables_invoice.tenant, v_row."company_id"::text, v_row."contact_id"::text, v_row."buyer"),
    'lines', v_lines,
    'tax_lines', (select case when count(*) = 0 then "better_supabase"."document_tax_summary"(v_lines) else jsonb_agg(jsonb_build_object(
      'taxRateBps', x."tax_rate_bps",
      'taxCode', x."tax_code",
      'net', (x."net")::bigint::text,
      'tax', (x."tax")::bigint::text,
      'gross', (x."gross")::bigint::text
    ) order by x."tax_rate_bps", x."tax_code") end
    from "better_supabase"."invoice_tax_lines" x
    where x."invoice_id" = v_row."id"),
    'totals', jsonb_build_object('listTotal', (v_row."list_total")::bigint::text, 'discountTotal', (v_row."discount_total")::bigint::text, 'subtotal', (v_row."subtotal")::bigint::text, 'taxTotal', (v_row."tax_total")::bigint::text, 'total', (v_row."total")::bigint::text, 'paidTotal', (v_row."paid_total")::bigint::text, 'creditedTotal', (v_row."credited_total")::bigint::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', case when document_variables_invoice.credit_note then null else (v_row."total" - v_row."paid_total" - v_row."credited_total")::bigint::text end),
    'payment_terms', jsonb_build_object('code', (select "code"::text from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'name', (select "name"::text from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'days', v_row."terms_days", 'dueOn', to_char(v_row."due_on", 'YYYY-MM-DD'), 'discountBps', (select "discount_bps" from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'discountDays', (select "discount_days" from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'discountDueOn', to_char(v_row."discount_due_on", 'YYYY-MM-DD'), 'discountAmount', (v_row."discount_amount_early")::bigint::text)
  );
end;
$$;
revoke execute on function "better_supabase"."document_variables_invoice"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."document_variables_invoice"(uuid, uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."document_variables_quote"(tenant uuid, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."quotes"%rowtype;
  v_lines jsonb;
begin
  select * into v_row from "better_supabase"."quotes" x
    where x."id" = document_variables_quote.document_id and x."tenant_id" = document_variables_quote.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_lines := (select coalesce(jsonb_agg(jsonb_build_object(
      'position', l.n,
      'description', l."description",
      'sku', null::text,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', trim_scale((l."quantity")::numeric)::text,
      'unitAmount', (l."unit_amount")::bigint::text,
      'discountBps', l."discount_bps",
      'discountAmount', (l."discount_amount")::bigint::text,
      'taxRateBps', l."tax_rate_bps",
      'taxCode', l."tax_code",
      'amount', (round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0))))::bigint::text
    ) order by l.n), '[]'::jsonb)
      from (
        select x.*, row_number() over (order by x."position", x."id") as n
        from "better_supabase"."quote_lines" x
        where x."parent_id" = v_row."id"
      ) l
      where (not l."optional" or l."selected"));
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', 'quote', 'number', coalesce(v_row."identifier", v_row."number"::text), 'title', v_row."title", 'status', v_row."status"::text, 'date', to_char(coalesce(v_row."sent_at", v_row."created_at") at time zone 'UTC', 'YYYY-MM-DD'), 'currency', trim(v_row."currency"), 'language', null::text, 'note', v_row."note", 'reference', null::text, 'validUntil', to_char(v_row."valid_until", 'YYYY-MM-DD'), 'revision', v_row."revision"),
    'entity', "better_supabase"."document_entity"(document_variables_quote.tenant, null::uuid),
    'buyer', "better_supabase"."document_party"(document_variables_quote.tenant, v_row."company_id"::text, v_row."contact_id"::text, v_row."buyer"),
    'lines', v_lines,
    'tax_lines', (select case when count(*) = 0 then "better_supabase"."document_tax_summary"(v_lines) else jsonb_agg(jsonb_build_object(
      'taxRateBps', x."tax_rate_bps",
      'taxCode', x."tax_code",
      'net', (x."net")::bigint::text,
      'tax', (x."tax")::bigint::text,
      'gross', (x."gross")::bigint::text
    ) order by x."tax_rate_bps", x."tax_code") end
    from "better_supabase"."quote_tax_lines" x
    where x."parent_id" = v_row."id"),
    'totals', jsonb_build_object('listTotal', (v_row."list_total")::bigint::text, 'discountTotal', (v_row."discount_total")::bigint::text, 'subtotal', (v_row."subtotal")::bigint::text, 'taxTotal', (v_row."tax_total")::bigint::text, 'total', (v_row."total")::bigint::text, 'paidTotal', null::text, 'creditedTotal', null::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', null::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', v_row."terms", 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text)
  );
end;
$$;
revoke execute on function "better_supabase"."document_variables_quote"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."document_variables_quote"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."document_variables_order"(tenant uuid, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."orders"%rowtype;
  v_lines jsonb;
begin
  select * into v_row from "better_supabase"."orders" x
    where x."id" = document_variables_order.document_id and x."tenant_id" = document_variables_order.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', l.n,
      'description', l."title",
      'sku', l."sku",
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', l."quantity"::text,
      'unitAmount', (l."unit_amount")::bigint::text,
      'discountBps', null::integer,
      'discountAmount', (l."discount")::bigint::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', (l."subtotal" - l."discount")::bigint::text
    ) order by l.n), '[]'::jsonb) into v_lines
  from (
    select x.*, row_number() over (order by x."position", x."id") as n
    from "better_supabase"."order_lines" x
    where x."order_id" = v_row."id"
  ) l;
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', 'order', 'number', v_row."number"::text, 'title', null::text, 'status', v_row."status"::text, 'date', to_char(v_row."placed_at" at time zone 'UTC', 'YYYY-MM-DD'), 'currency', trim(v_row."currency"), 'language', null::text, 'note', null::text, 'reference', null::text),
    'entity', "better_supabase"."document_entity"(document_variables_order.tenant, null::uuid),
    'buyer', "better_supabase"."document_party"(document_variables_order.tenant, v_row."customer_id"::text, v_row."customer_id"::text, v_row."buyer", v_row."email", v_row."billing_address"),
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', (v_row."discount_total")::bigint::text, 'subtotal', (v_row."subtotal")::bigint::text, 'taxTotal', (v_row."tax_total")::bigint::text, 'total', (v_row."total")::bigint::text, 'paidTotal', (v_row."paid_total")::bigint::text, 'creditedTotal', (v_row."refunded_total")::bigint::text, 'shippingTotal', (v_row."shipping_total")::bigint::text, 'fee', null::text, 'balance', (v_row."total" - v_row."paid_total" + v_row."refunded_total")::bigint::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text),
    'shipping', jsonb_build_object('address', "better_supabase"."document_address"(v_row."shipping_address"), 'carrier', (select x."carrier"::text from "better_supabase"."order_fulfillments" x where x."order_id" = v_row."id" order by x."created_at" desc limit 1), 'trackingNumber', (select x."tracking_number"::text from "better_supabase"."order_fulfillments" x where x."order_id" = v_row."id" order by x."created_at" desc limit 1))
  );
end;
$$;
revoke execute on function "better_supabase"."document_variables_order"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."document_variables_order"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."document_variables_delivery_note"(tenant uuid, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shipments"%rowtype;
  v_lines jsonb;
  v_customer text;
  v_buyer jsonb;
  v_email text;
begin
  select * into v_row from "better_supabase"."shipments" x
    where x."id" = document_variables_delivery_note.document_id and x."tenant_id" = document_variables_delivery_note.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if v_row."subject_type" = 'order' then
    select o."customer_id"::text, o."buyer", o."email"
      into v_customer, v_buyer, v_email
      from "better_supabase"."orders" o
      where o."id"::text = v_row."subject_id" and o."tenant_id" = document_variables_delivery_note.tenant;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', n.sku,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', n.quantity,
      'unitAmount', null::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', null::text
    ) order by n.n), '[]'::jsonb) into v_lines
  from (
    select row_number() over (order by x."position", x."id") as n,
      coalesce(ol."title", x."variant_id"::text) as description,
      ol."sku" as sku,
      trim_scale((x."quantity")::numeric)::text as quantity
    from "better_supabase"."shipment_lines" x
    left join "better_supabase"."order_lines" ol on v_row."subject_type" = 'order' and ol."order_id"::text = v_row."subject_id" and ol."variant_id" = x."variant_id"
    where x."shipment_id" = v_row."id" and x."direction" = 'outbound'
  ) n;
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', 'delivery_note', 'number', v_row."reference", 'title', null::text, 'status', v_row."status"::text, 'date', to_char(coalesce(v_row."labeled_at", v_row."created_at") at time zone 'UTC', 'YYYY-MM-DD'), 'currency', null::text, 'language', null::text, 'note', null::text, 'reference', v_row."tracking_number"),
    'entity', "better_supabase"."document_entity"(document_variables_delivery_note.tenant, null::uuid),
    'buyer', "better_supabase"."document_party"(document_variables_delivery_note.tenant, v_customer, v_customer, v_buyer, v_email, v_row."to_address"),
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', null::text, 'subtotal', null::text, 'taxTotal', null::text, 'total', null::text, 'paidTotal', null::text, 'creditedTotal', null::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', null::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text),
    'shipping', jsonb_build_object('address', "better_supabase"."document_address"(v_row."to_address"), 'carrier', v_row."carrier", 'trackingNumber', v_row."tracking_number")
  );
end;
$$;
revoke execute on function "better_supabase"."document_variables_delivery_note"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."document_variables_delivery_note"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."document_variables_dunning_letter"(tenant uuid, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item "better_supabase"."invoice_dunning_run_items"%rowtype;
  v_as_of date;
  v_lines jsonb;
  v_fee bigint;
  v_balance bigint;
  v_level integer;
  v_due date;
  v_currency text;
begin
  select * into v_item from "better_supabase"."invoice_dunning_run_items" x
    where x."id" = document_variables_dunning_letter.document_id and x."tenant_id" = document_variables_dunning_letter.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select x."as_of" into v_as_of from "better_supabase"."invoice_dunning_runs" x where x."id" = v_item."run_id";
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', null::text,
      'reference', n.number,
      'date', n.issued_on,
      'dueOn', n.due_on,
      'quantity', '1',
      'unitAmount', n.balance::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', n.balance::text
    ) order by n.n), '[]'::jsonb),
    coalesce(sum(n.fee), 0), coalesce(sum(n.balance), 0), max(n.level), min(n.due), max(n.currency)
  into v_lines, v_fee, v_balance, v_level, v_due, v_currency
  from (
    select row_number() over (order by x."due_on", x."id") as n,
      coalesce(i."title", i."identifier") as description,
      coalesce(i."identifier", i."number"::text) as number,
      to_char(i."issued_on", 'YYYY-MM-DD') as issued_on,
      to_char(x."due_on", 'YYYY-MM-DD') as due_on,
      x."due_on" as due,
      x."balance" as balance,
      x."fee" as fee,
      x."level" as level,
      trim(i."currency") as currency
    from "better_supabase"."invoice_dunning_run_items" x
    join "better_supabase"."invoices" i on i."id" = x."invoice_id"
    where x."run_id" = v_item."run_id"
      and x."party_id" is not distinct from v_item."party_id"
  ) n;
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_item."id"::text, 'type', 'dunning_letter', 'number', null::text, 'title', null::text, 'status', null::text, 'date', to_char(v_as_of, 'YYYY-MM-DD'), 'currency', v_currency, 'language', null::text, 'note', null::text, 'reference', null::text, 'dueOn', to_char(v_due, 'YYYY-MM-DD'), 'level', v_level, 'asOf', to_char(v_as_of, 'YYYY-MM-DD'), 'textKey', v_item."text_key"),
    'entity', "better_supabase"."document_entity"(document_variables_dunning_letter.tenant, null::uuid),
    'buyer', "better_supabase"."document_party"(document_variables_dunning_letter.tenant, v_item."party_id"::text, null),
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', null::text, 'subtotal', null::text, 'taxTotal', null::text, 'total', (v_balance + v_fee)::bigint::text, 'paidTotal', null::text, 'creditedTotal', null::text, 'shippingTotal', null::text, 'fee', (v_fee)::bigint::text, 'balance', (v_balance + v_fee)::bigint::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text)
  );
end;
$$;
revoke execute on function "better_supabase"."document_variables_dunning_letter"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."document_variables_dunning_letter"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."document_variables_statement"(tenant uuid, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_lines jsonb;
  v_total bigint;
  v_paid bigint;
  v_credited bigint;
  v_balance bigint;
  v_currency text;
  v_party jsonb;
begin
  v_party := "better_supabase"."document_party"(document_variables_statement.tenant, document_variables_statement.document_id::text, document_variables_statement.document_id::text);
  if v_party ->> 'id' is null then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', null::text,
      'reference', n.number,
      'date', n.issued_on,
      'dueOn', n.due_on,
      'quantity', '1',
      'unitAmount', n.balance::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', n.balance::text
    ) order by n.n), '[]'::jsonb),
    coalesce(sum(n.total), 0), coalesce(sum(n.paid), 0), coalesce(sum(n.credited), 0), coalesce(sum(n.balance), 0), max(n.currency)
  into v_lines, v_total, v_paid, v_credited, v_balance, v_currency
  from (
    select row_number() over (order by x."due_on", x."id") as n,
      coalesce(x."title", x."identifier") as description,
      coalesce(x."identifier", x."number"::text) as number,
      to_char(x."issued_on", 'YYYY-MM-DD') as issued_on,
      to_char(x."due_on", 'YYYY-MM-DD') as due_on,
      x."total" as total,
      x."paid_total" as paid,
      x."credited_total" as credited,
      x."total" - x."paid_total" - x."credited_total" as balance,
      trim(x."currency") as currency
    from "better_supabase"."invoices" x
    where x."tenant_id" = document_variables_statement.tenant and (x."company_id"::text = document_variables_statement.document_id::text or x."contact_id"::text = document_variables_statement.document_id::text)
      and x."status" in ('issued', 'partially_paid') and x."kind" = 'invoice' and x."direction" = 'sales'
      and x."total" - x."paid_total" - x."credited_total" > 0
  ) n;
  return jsonb_build_object(
    'document', jsonb_build_object('id', document_variables_statement.document_id::text, 'type', 'statement', 'number', null::text, 'title', null::text, 'status', null::text, 'date', to_char(current_date, 'YYYY-MM-DD'), 'currency', v_currency, 'language', null::text, 'note', null::text, 'reference', null::text, 'asOf', to_char(current_date, 'YYYY-MM-DD')),
    'entity', "better_supabase"."document_entity"(document_variables_statement.tenant, null::uuid),
    'buyer', v_party,
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', null::text, 'subtotal', null::text, 'taxTotal', null::text, 'total', (v_total)::bigint::text, 'paidTotal', (v_paid)::bigint::text, 'creditedTotal', (v_credited)::bigint::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', (v_balance)::bigint::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text)
  );
end;
$$;
revoke execute on function "better_supabase"."document_variables_statement"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."document_variables_statement"(uuid, uuid) to authenticated, service_role;

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
    when 'invoice' then return "better_supabase"."document_variables_invoice"(document_variables.tenant, document_id, false);
    when 'credit_note' then return "better_supabase"."document_variables_invoice"(document_variables.tenant, document_id, true);
    when 'quote' then return "better_supabase"."document_variables_quote"(document_variables.tenant, document_id);
    when 'order' then return "better_supabase"."document_variables_order"(document_variables.tenant, document_id);
    when 'delivery_note' then return "better_supabase"."document_variables_delivery_note"(document_variables.tenant, document_id);
    when 'dunning_letter' then return "better_supabase"."document_variables_dunning_letter"(document_variables.tenant, document_id);
    when 'statement' then return "better_supabase"."document_variables_statement"(document_variables.tenant, document_id);
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
    perform "better_supabase".emit_event('document_template.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.updated',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'updated ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
  else
    insert into "better_supabase"."document_templates" ("tenant_id", "legal_entity_id", "document_type", "language", "name", "body", "active")
    values (save_document_template.tenant, save_document_template.legal_entity_id, save_document_template.document_type, v_language, v_name, save_document_template.body, v_active)
    returning * into v_row;
    perform "better_supabase".emit_event('document_template.created', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.created',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'created ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
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
    perform "better_supabase".emit_event('document_template.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.updated',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'updated ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
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
    perform "better_supabase".emit_event('document_text_block.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_text_block.updated',
    category => 'data',
    target_type => 'document_text_block',
    record_id => v_row."id"::text,
    summary => 'updated text block ' || v_row."key" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version")
  );
  else
    insert into "better_supabase"."document_text_blocks" ("tenant_id", "legal_entity_id", "key", "language", "body")
    values (save_document_text_block.tenant, save_document_text_block.legal_entity_id, save_document_text_block.key, v_language, save_document_text_block.body)
    returning * into v_row;
    perform "better_supabase".emit_event('document_text_block.created', jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_text_block.created',
    category => 'data',
    target_type => 'document_text_block',
    record_id => v_row."id"::text,
    summary => 'created text block ' || v_row."key" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version")
  );
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
  perform "better_supabase".emit_event('document_snapshot.created', jsonb_build_object('organizationId', v_row."tenant_id", 'snapshotId', v_row."id", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'templateVersion', v_row."template_version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_snapshot.created',
    category => 'data',
    target_type => 'document_snapshot',
    record_id => v_row."id"::text,
    summary => 'froze ' || v_row."document_type" || ' ' || v_row."document_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'snapshotId', v_row."id", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'templateVersion', v_row."template_version")
  );
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


create or replace function "better_supabase"."freeze_issued_invoice"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is not null then
    return null;
  end if;
  begin
    perform "better_supabase"."document_freeze"(new."tenant_id", case when new."kind" = 'credit_note' then 'credit_note' else 'invoice' end, new."id", null, null);
  exception when others then
    raise warning 'the document snapshot of invoice % was skipped: %', new."id", sqlerrm;
  end;
  return null;
end;
$$;
revoke execute on function "better_supabase"."freeze_issued_invoice"() from public, anon, authenticated;
drop trigger if exists bsb_document_freeze on "better_supabase"."invoices";
create constraint trigger bsb_document_freeze
  after update of "status" on "better_supabase"."invoices"
  deferrable initially deferred
  for each row
  when (old."status" = 'draft' and new."status" not in ('draft', 'void'))
  execute function "better_supabase"."freeze_issued_invoice"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."document_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_templates";
create policy bsb_tenant_scope_select on "better_supabase"."document_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."document_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_templates";
create policy bsb_tenant_scope_update on "better_supabase"."document_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."document_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."document_text_blocks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_select on "better_supabase"."document_text_blocks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_insert on "better_supabase"."document_text_blocks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_update on "better_supabase"."document_text_blocks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_delete on "better_supabase"."document_text_blocks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rendered_documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_select on "better_supabase"."rendered_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("tenant_id", "document_type", "document_id") end))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_insert on "better_supabase"."rendered_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_update on "better_supabase"."rendered_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_delete on "better_supabase"."rendered_documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block-data document-templates
-- @bsb-hash sha256:9583aaa09d07839093d6d62721ded388961f4622fdffe43a1e36011ffc2c8765
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.document_templates', target_type => 'document_template', event_prefix => 'document_template', deferred => true);
select better_supabase.audit('better_supabase.document_text_blocks', target_type => 'document_text_block', event_prefix => 'document_text_block', deferred => true);
select better_supabase.audit('better_supabase.rendered_documents', target_type => 'document_snapshot', event_prefix => 'document_snapshot', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('document-templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block document-templates@1 managed
-- @bsb-hash sha256:0052fb51a879dabf8e7f4d59ca55ace1bc0b8bfa3383f86d9faa6d3e78162eed
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
    drop policy if exists bsb_tenant_scope on "app_private"."document_templates";
    drop policy if exists bsb_tenant_scope_select on "app_private"."document_templates";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."document_templates";
    drop policy if exists bsb_tenant_scope_update on "app_private"."document_templates";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."document_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_select on "app_private"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_update on "app_private"."document_text_blocks";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."document_text_blocks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."rendered_documents";
    drop policy if exists bsb_tenant_scope_select on "app_private"."rendered_documents";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."rendered_documents";
    drop policy if exists bsb_tenant_scope_update on "app_private"."rendered_documents";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."rendered_documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Document templates (ADR 0145): per legal entity and language templates, text
-- blocks, one variable contract per document type, render_document and the
-- snapshots that keep an issued document stable.

-- One address in the contract's six keys, from the key names addresses use.
create or replace function "app_private"."document_address"(address jsonb)
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
revoke execute on function "app_private"."document_address"(jsonb) from public, anon;
grant execute on function "app_private"."document_address"(jsonb) to authenticated, service_role;

-- The legal entity that issues a document: the given one, else the
-- organization's default. All null when the organization has none.
create or replace function "app_private"."document_entity"(tenant uuid, legal_entity uuid default null)
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
  return jsonb_build_object('id', v_row."id", 'code', v_row."code", 'name', v_row."name", 'address', "app_private"."document_address"(v_row."address"), 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency");
end;
$$;
revoke execute on function "app_private"."document_entity"(uuid, uuid) from public, anon;
grant execute on function "app_private"."document_entity"(uuid, uuid) to authenticated, service_role;

-- The customer of a document. The buyer the document stored comes first, then
-- the company, then the person; address is the fallback address.
create or replace function "app_private"."document_party"(tenant uuid, company_id text, contact_id text, buyer jsonb default null, email text default null, address jsonb default null)
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
    'address', "app_private"."document_address"(coalesce(case when jsonb_typeof(v_buyer -> 'address') = 'object' then v_buyer -> 'address' end, document_party.address))
  );
end;
$$;
revoke execute on function "app_private"."document_party"(uuid, text, text, jsonb, text, jsonb) from public, anon;
grant execute on function "app_private"."document_party"(uuid, text, text, jsonb, text, jsonb) to authenticated, service_role;

-- The tax per rate and code of a lines array, counted from the line amounts.
create or replace function "app_private"."document_tax_summary"(lines jsonb)
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
revoke execute on function "app_private"."document_tax_summary"(jsonb) from public, anon;
grant execute on function "app_private"."document_tax_summary"(jsonb) to authenticated, service_role;

-- Whether the caller can read the source row of a document.
create or replace function "app_private"."document_visible"(tenant uuid, document_type text, document_id uuid)
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
revoke execute on function "app_private"."document_visible"(uuid, text, uuid) from public, anon;
grant execute on function "app_private"."document_visible"(uuid, text, uuid) to authenticated, service_role;

-- The variable payload of one document, in the shape of the contract. The
-- caller reads the source rows through row level security. The document
-- language and the template are added by render_document.
create or replace function "app_private"."document_variables"(tenant uuid, document_type text, document_id uuid)
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
revoke execute on function "app_private"."document_variables"(uuid, text, uuid) from public, anon;
grant execute on function "app_private"."document_variables"(uuid, text, uuid) to authenticated, service_role;


-- The templates of an organization, per document type, name, legal entity
-- (null for the organization) and language (null for any).
create table if not exists "app_private"."document_templates" (
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
create unique index if not exists "document_templates_slot_idx" on "app_private"."document_templates" ("tenant_id", "document_type", "name", coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid), coalesce("language", ''));
create index if not exists "document_templates_lookup_idx" on "app_private"."document_templates" ("tenant_id", "document_type", "name") where "active";
create index if not exists "document_templates_entity_idx" on "app_private"."document_templates" ("tenant_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_templates_created_by_idx" on "app_private"."document_templates" ("created_by") where "created_by" is not null;
alter table "app_private"."document_templates" enable row level security;
revoke all on "app_private"."document_templates" from public, anon, authenticated;
grant select on "app_private"."document_templates" to authenticated;
grant all on "app_private"."document_templates" to service_role;
drop policy if exists document_templates_read on "app_private"."document_templates";
create policy document_templates_read on "app_private"."document_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- Reusable texts, read in a template as texts.<key>.
create table if not exists "app_private"."document_text_blocks" (
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
create unique index if not exists "document_text_blocks_slot_idx" on "app_private"."document_text_blocks" ("tenant_id", "key", coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid), coalesce("language", ''));
create index if not exists "document_text_blocks_entity_idx" on "app_private"."document_text_blocks" ("tenant_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_text_blocks_created_by_idx" on "app_private"."document_text_blocks" ("created_by") where "created_by" is not null;
alter table "app_private"."document_text_blocks" enable row level security;
revoke all on "app_private"."document_text_blocks" from public, anon, authenticated;
grant select on "app_private"."document_text_blocks" to authenticated;
grant all on "app_private"."document_text_blocks" to service_role;
drop policy if exists document_text_blocks_read on "app_private"."document_text_blocks";
create policy document_text_blocks_read on "app_private"."document_text_blocks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- What a document looked like when it was frozen: its variables, the template
-- and the text blocks it used. A snapshot never changes. The template column
-- keeps the body, so deleting or editing the template leaves it as it was.
create table if not exists "app_private"."rendered_documents" (
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
create index if not exists "rendered_documents_created_by_idx" on "app_private"."rendered_documents" ("created_by") where "created_by" is not null;
alter table "app_private"."rendered_documents" enable row level security;
revoke all on "app_private"."rendered_documents" from public, anon, authenticated;
grant select on "app_private"."rendered_documents" to authenticated;
grant all on "app_private"."rendered_documents" to service_role;
-- A snapshot shows to someone who can read the document it froze; a statement
-- has no row of its own, so it shows to the template managers.
drop policy if exists rendered_documents_read on "app_private"."rendered_documents";
create policy rendered_documents_read on "app_private"."rendered_documents"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "app_private"."document_visible"("tenant_id", "document_type", "document_id") end));


-- The variable contract of a document type: its version and the paths and
-- types a template can read. Null names every type. A text block reads any of
-- them. The TypeScript type DocumentVariables and the JSON Schema in
-- schemas/document-template-variables-v1.json state the same contract.
create or replace function "app_private"."document_template_contract"(document_type text default null)
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
revoke execute on function "app_private"."document_template_contract"(text) from public, anon;
grant execute on function "app_private"."document_template_contract"(text) to authenticated, service_role;

-- The problems of a template body, first to last, as [{ code, message, tag }].
-- Empty when the body is valid. A text block (text_block) may read the
-- variables of any document type and has no texts.<key>. An unknown variable,
-- an unknown filter and a block that is not closed each have a hint code.
create or replace function "app_private"."validate_document_template"(document_type text, body text, text_block boolean default false)
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
    for v_contract in select c.value from jsonb_each("app_private"."document_template_contract"(null)) c loop
      for v_item in select e.value from jsonb_array_elements(v_contract -> 'variables') e loop
        v_known := v_known || jsonb_build_object(v_item ->> 'path', v_item ->> 'type');
      end loop;
    end loop;
  else
    for v_item in select e.value from jsonb_array_elements("app_private"."document_template_contract"(validate_document_template.document_type) -> 'variables') e loop
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
revoke execute on function "app_private"."validate_document_template"(text, text, boolean) from public, anon;
grant execute on function "app_private"."validate_document_template"(text, text, boolean) to authenticated, service_role;

-- Raises with the hint code of the first problem of a template body.
create or replace function "app_private"."assert_document_template"(document_type text, body text, text_block boolean default false)
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
  v_issues := "app_private"."validate_document_template"(assert_document_template.document_type, assert_document_template.body, assert_document_template.text_block);
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
revoke execute on function "app_private"."assert_document_template"(text, text, boolean) from public, anon, authenticated;

-- How well a template or text block fits a request, lower first: its own
-- entity before the organization's, and inside each its exact language, its
-- base language (nl for nl-nl), then no language, then any other language.
create or replace function "app_private"."document_slot_rank"(entity uuid, wanted_entity uuid, language text, wanted_language text)
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
revoke execute on function "app_private"."document_slot_rank"(uuid, uuid, text, text) from public, anon;
grant execute on function "app_private"."document_slot_rank"(uuid, uuid, text, text) to authenticated, service_role;

-- Saves the template of a slot: a document type, a name, a legal entity (null
-- for the organization) and a language (null for any). Saving a changed body
-- raises the version by one; the same body and state change nothing. Raises
-- with a hint code when the body names an unknown variable.
create or replace function "app_private"."save_document_template"(tenant uuid, document_type text, body text, language text default null, name text default 'default', legal_entity_id uuid default null, active boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."document_templates"%rowtype;
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
  perform "app_private"."assert_document_template"(save_document_template.document_type, save_document_template.body);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_template_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_document_template.tenant, save_document_template.document_type;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('document_templates:' || save_document_template.tenant::text, 0));
  select * into v_row from "app_private"."document_templates" t
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
    update "app_private"."document_templates" t set
      "body" = save_document_template.body,
      "version" = t."version" + case when v_changed then 1 else 0 end,
      "active" = v_active,
      "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    null;
  else
    insert into "app_private"."document_templates" ("tenant_id", "legal_entity_id", "document_type", "language", "name", "body", "active")
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
revoke execute on function "app_private"."save_document_template"(uuid, text, text, text, text, uuid, boolean) from public, anon;
grant execute on function "app_private"."save_document_template"(uuid, text, text, text, text, uuid, boolean) to authenticated, service_role;

-- Turns a template on or off. An inactive template drops out of the fallback
-- chain; documents already frozen keep the copy they froze.
create or replace function "app_private"."set_document_template_active"(template_id uuid, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."document_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."document_templates" t where t."id" = set_document_template_active.template_id;
  if not found then
    raise exception 'document template not found' using errcode = 'P0002', hint = 'DOCUMENT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if v_row."active" is distinct from coalesce(set_document_template_active.active, true) then
    update "app_private"."document_templates" t set "active" = coalesce(set_document_template_active.active, true), "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."set_document_template_active"(uuid, boolean) from public, anon;
grant execute on function "app_private"."set_document_template_active"(uuid, boolean) to authenticated, service_role;

create or replace function "app_private"."get_document_template"(template_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."document_templates"%rowtype;
begin
  select * into v_row from "app_private"."document_templates" t where t."id" = get_document_template.template_id;
  if not found then
    raise exception 'document template not found' using errcode = 'P0002', hint = 'DOCUMENT_TEMPLATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."get_document_template"(uuid) from public, anon;
grant execute on function "app_private"."get_document_template"(uuid) to authenticated, service_role;

-- The templates of an organization by document type, name, entity (the
-- organization's first) and language.
create or replace function "app_private"."list_document_templates"(tenant uuid, document_type text default null, legal_entity_id uuid default null, active_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") order by t."document_type", t."name", t."legal_entity_id" nulls first, t."language" nulls first), '[]'::jsonb)
  from "app_private"."document_templates" t
  where t."tenant_id" = list_document_templates.tenant
    and (list_document_templates.document_type is null or t."document_type" = list_document_templates.document_type)
    and (list_document_templates.legal_entity_id is null or t."legal_entity_id" = list_document_templates.legal_entity_id)
    and (not coalesce(list_document_templates.active_only, false) or t."active")
$$;
revoke execute on function "app_private"."list_document_templates"(uuid, text, uuid, boolean) from public, anon;
grant execute on function "app_private"."list_document_templates"(uuid, text, uuid, boolean) to authenticated, service_role;

-- Saves a reusable text, read in a template as texts.<key>: a payment terms
-- sentence, a dunning text, a footer, a legal line. The text may hold the same
-- placeholders a template does, of any document type. An entity text beats the
-- organization's, and an exact language beats a text with no language.
create or replace function "app_private"."save_document_text_block"(tenant uuid, key text, body text, language text default null, legal_entity_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."document_text_blocks"%rowtype;
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
  perform "app_private"."assert_document_template"(null, save_document_text_block.body, true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_text_block_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_document_text_block.tenant, save_document_text_block.key;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('document_text_blocks:' || save_document_text_block.tenant::text, 0));
  select * into v_row from "app_private"."document_text_blocks" b
    where b."tenant_id" = save_document_text_block.tenant
      and b."key" = save_document_text_block.key
      and b."legal_entity_id" is not distinct from save_document_text_block.legal_entity_id
      and b."language" is not distinct from v_language;
  if found then
    if v_row."body" = save_document_text_block.body then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'key', v_row."key", 'language', v_row."language", 'body', v_row."body", 'version', v_row."version", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    update "app_private"."document_text_blocks" b set "body" = save_document_text_block.body, "version" = b."version" + 1, "updated_at" = now()
    where b."id" = v_row."id"
    returning * into v_row;
    null;
  else
    insert into "app_private"."document_text_blocks" ("tenant_id", "legal_entity_id", "key", "language", "body")
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
revoke execute on function "app_private"."save_document_text_block"(uuid, text, text, text, uuid) from public, anon;
grant execute on function "app_private"."save_document_text_block"(uuid, text, text, text, uuid) to authenticated, service_role;

create or replace function "app_private"."list_document_text_blocks"(tenant uuid, key text default null, legal_entity_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', b."id", 'organizationId', b."tenant_id", 'legalEntityId', b."legal_entity_id", 'key', b."key", 'language', b."language", 'body', b."body", 'version', b."version", 'createdAt', b."created_at", 'updatedAt', b."updated_at") order by b."key", b."legal_entity_id" nulls first, b."language" nulls first), '[]'::jsonb)
  from "app_private"."document_text_blocks" b
  where b."tenant_id" = list_document_text_blocks.tenant
    and (list_document_text_blocks.key is null or b."key" = list_document_text_blocks.key)
    and (list_document_text_blocks.legal_entity_id is null or b."legal_entity_id" = list_document_text_blocks.legal_entity_id)
$$;
revoke execute on function "app_private"."list_document_text_blocks"(uuid, text, uuid) from public, anon;
grant execute on function "app_private"."list_document_text_blocks"(uuid, text, uuid) to authenticated, service_role;

-- The template a document gets: the legal entity's template in the document's
-- language, the entity's template for any language, the organization's in the
-- language, then the organization's for any language. Legal entity null means
-- the default entity. A language also matches by its base (nl for nl-nl), and a
-- template in another language is the last resort. Null when nothing fits.
create or replace function "app_private"."resolve_document_template"(tenant uuid, document_type text, legal_entity_id uuid default null, language text default null, name text default 'default')
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
  v_row "app_private"."document_templates"%rowtype;
  v_rank integer;
begin
  v_entity := "better_supabase"."legal_entity_of"(resolve_document_template.tenant, resolve_document_template.legal_entity_id);
  select * into v_row
  from "app_private"."document_templates" t
  where t."tenant_id" = resolve_document_template.tenant
    and t."document_type" = resolve_document_template.document_type
    and t."name" = coalesce(resolve_document_template.name, 'default')
    and t."active"
    and (t."legal_entity_id" is null or t."legal_entity_id" = v_entity)
  order by "app_private"."document_slot_rank"(t."legal_entity_id", v_entity, t."language", v_language), t."updated_at" desc
  limit 1;
  if not found then
    return null;
  end if;
  v_rank := "app_private"."document_slot_rank"(v_row."legal_entity_id", v_entity, v_row."language", v_language);
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
revoke execute on function "app_private"."resolve_document_template"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "app_private"."resolve_document_template"(uuid, text, uuid, text, text) to authenticated, service_role;

-- The text blocks for these keys, as an object of key to body, each chosen by
-- the same chain as a template. A key with no block is left out.
create or replace function "app_private"."resolve_document_blocks"(tenant uuid, keys text[], legal_entity_id uuid default null, language text default null)
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
    from "app_private"."document_text_blocks" b
    where b."tenant_id" = resolve_document_blocks.tenant
      and b."key" = any (coalesce(resolve_document_blocks.keys, '{}'::text[]))
      and (b."legal_entity_id" is null or b."legal_entity_id" = v_entity)
    order by b."key", "app_private"."document_slot_rank"(b."legal_entity_id", v_entity, b."language", v_language), b."updated_at" desc
  ) f;
  return v_result;
end;
$$;
revoke execute on function "app_private"."resolve_document_blocks"(uuid, text[], uuid, text) from public, anon;
grant execute on function "app_private"."resolve_document_blocks"(uuid, text[], uuid, text) to authenticated, service_role;

-- The variables, the chosen template and its text blocks for a document as it
-- stands now. The language is the one asked for, else the buyer's.
create or replace function "app_private"."document_render_live"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
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
  v_vars := "app_private"."document_variables"(document_render_live.tenant, document_render_live.document_type, document_render_live.document_id);
  v_entity := nullif(v_vars #>> '{entity,id}', '')::uuid;
  v_language := coalesce(v_language, lower(nullif(btrim(v_vars #>> '{buyer,language}'), '')));
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    v_language := null;
  end if;
  v_template := "app_private"."resolve_document_template"(document_render_live.tenant, document_render_live.document_type, v_entity, v_language, coalesce(document_render_live.template_name, 'default'));
  if v_template is not null then
    select coalesce(array_agg(distinct m[1]), '{}'::text[]) into v_keys
    from regexp_matches(v_template ->> 'body', 'texts\.([a-z][a-z0-9_]{0,63})', 'g') m;
    v_text_key := nullif(v_vars #>> '{document,textKey}', '');
    if v_text_key is not null and v_text_key ~ '^[a-z][a-z0-9_]{0,63}$' and not v_text_key = any (v_keys) then
      v_keys := v_keys || v_text_key;
    end if;
    v_blocks := "app_private"."resolve_document_blocks"(document_render_live.tenant, v_keys, v_entity, v_language);
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
revoke execute on function "app_private"."document_render_live"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "app_private"."document_render_live"(uuid, text, uuid, text, text) to authenticated, service_role;

-- Everything a renderer needs for one document: the variable payload, the
-- chosen template and the text blocks it reads. A document that was frozen
-- (an issued invoice or credit note, or after freeze_document) returns the
-- copy it froze, so editing a template later never changes it; fresh = true
-- renders the document as it stands now with today's templates instead.
create or replace function "app_private"."render_document"(tenant uuid, document_type text, document_id uuid, language text default null, fresh boolean default false, template_name text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."rendered_documents"%rowtype;
begin
  if render_document.document_type is null or render_document.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  if not coalesce(render_document.fresh, false) then
    select * into v_row from "app_private"."rendered_documents" s
      where s."tenant_id" = render_document.tenant
        and s."document_type" = render_document.document_type
        and s."document_id" = render_document.document_id;
    if found then
      return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
    end if;
  end if;
  return "app_private"."document_render_live"(render_document.tenant, render_document.document_type, render_document.document_id, render_document.language, render_document.template_name);
end;
$$;
revoke execute on function "app_private"."render_document"(uuid, text, uuid, text, boolean, text) from public, anon;
grant execute on function "app_private"."render_document"(uuid, text, uuid, text, boolean, text) to authenticated, service_role;

-- Freezes a document: stores the variables, the template and the text blocks
-- as they are now. A frozen document returns its snapshot unchanged.
create or replace function "app_private"."document_freeze"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."rendered_documents"%rowtype;
  v_live jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('rendered_documents:' || document_freeze.tenant::text || ':' || document_freeze.document_id::text, 0));
  select * into v_row from "app_private"."rendered_documents" s
    where s."tenant_id" = document_freeze.tenant
      and s."document_type" = document_freeze.document_type
      and s."document_id" = document_freeze.document_id;
  if found then
    return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
  end if;
  v_live := "app_private"."document_render_live"(document_freeze.tenant, document_freeze.document_type, document_freeze.document_id, document_freeze.language, document_freeze.template_name);
  insert into "app_private"."rendered_documents" ("tenant_id", "document_type", "document_id", "language", "legal_entity_id", "contract_version", "template_id", "template_version", "template", "blocks", "variables")
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
revoke execute on function "app_private"."document_freeze"(uuid, text, uuid, text, text) from public, anon, authenticated;

-- Freezes a document on request. An invoice and a credit note freeze when they
-- are issued; call this for the other documents when you send them.
create or replace function "app_private"."freeze_document"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
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
  return "app_private"."document_freeze"(freeze_document.tenant, freeze_document.document_type, freeze_document.document_id, freeze_document.language, freeze_document.template_name);
end;
$$;
revoke execute on function "app_private"."freeze_document"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "app_private"."freeze_document"(uuid, text, uuid, text, text) to authenticated, service_role;

-- A snapshot never changes; to freeze again, delete it first.
create or replace function "app_private"."document_snapshot_immutable"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a frozen document never changes' using errcode = '23000', hint = 'DOCUMENT_SNAPSHOT_IMMUTABLE';
end;
$$;
revoke execute on function "app_private"."document_snapshot_immutable"() from public, anon, authenticated;
drop trigger if exists bsb_frozen_render_guard on "app_private"."rendered_documents";
create trigger bsb_frozen_render_guard
  before update on "app_private"."rendered_documents"
  for each row execute function "app_private"."document_snapshot_immutable"();


-- item.data is { documentType, body, name?, language?, legalEntityId? or
-- legalEntity? (a code), active? }. The slot is the document type, name, legal
-- entity and language; importing it again changes the body and raises the version.
create or replace function "app_private"."import_document_template"(run uuid, item jsonb, subject_id text)
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
  v_saved := "app_private"."save_document_template"(v_tenant, v_data ->> 'documentType', v_data ->> 'body', v_data ->> 'language',
    coalesce(nullif(v_data ->> 'name', ''), 'default'), v_entity, coalesce((v_data ->> 'active')::boolean, true));
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$$;
revoke execute on function "app_private"."import_document_template"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."import_document_template"(uuid, jsonb, text) to service_role;

-- item.data is { key, body, language?, legalEntityId? or legalEntity? }.
create or replace function "app_private"."import_document_text_block"(run uuid, item jsonb, subject_id text)
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
  v_saved := "app_private"."save_document_text_block"(v_tenant, v_data ->> 'key', v_data ->> 'body', v_data ->> 'language', v_entity);
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$$;
revoke execute on function "app_private"."import_document_text_block"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."import_document_text_block"(uuid, jsonb, text) to service_role;

-- When a template or text block last changed, for the conflict check of imports.
create or replace function "app_private"."document_template_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select t."updated_at" from "app_private"."document_templates" t where t."id" = $1::uuid
$$;
revoke execute on function "app_private"."document_template_updated_at"(text) from public, anon, authenticated;
grant execute on function "app_private"."document_template_updated_at"(text) to service_role;

create or replace function "app_private"."document_text_block_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select b."updated_at" from "app_private"."document_text_blocks" b where b."id" = $1::uuid
$$;
revoke execute on function "app_private"."document_text_block_updated_at"(text) from public, anon, authenticated;
grant execute on function "app_private"."document_text_block_updated_at"(text) to service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."document_templates";
drop policy if exists bsb_tenant_scope_select on "app_private"."document_templates";
create policy bsb_tenant_scope_select on "app_private"."document_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."document_templates";
create policy bsb_tenant_scope_insert on "app_private"."document_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."document_templates";
create policy bsb_tenant_scope_update on "app_private"."document_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."document_templates";
create policy bsb_tenant_scope_delete on "app_private"."document_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."document_text_blocks";
drop policy if exists bsb_tenant_scope_select on "app_private"."document_text_blocks";
create policy bsb_tenant_scope_select on "app_private"."document_text_blocks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."document_text_blocks";
create policy bsb_tenant_scope_insert on "app_private"."document_text_blocks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."document_text_blocks";
create policy bsb_tenant_scope_update on "app_private"."document_text_blocks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."document_text_blocks";
create policy bsb_tenant_scope_delete on "app_private"."document_text_blocks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."rendered_documents";
drop policy if exists bsb_tenant_scope_select on "app_private"."rendered_documents";
create policy bsb_tenant_scope_select on "app_private"."rendered_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "app_private"."document_visible"("tenant_id", "document_type", "document_id") end))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."rendered_documents";
create policy bsb_tenant_scope_insert on "app_private"."rendered_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."rendered_documents";
create policy bsb_tenant_scope_update on "app_private"."rendered_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."rendered_documents";
create policy bsb_tenant_scope_delete on "app_private"."rendered_documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_163_document_templates.sql
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

-- ==== api schema: schema supabase/schemas/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block document-templates@1 managed
-- @bsb-hash sha256:9c6b41377f46db1602307f83fab6928f282727ba0f9ebaed2640278b7a690d47
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
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."document_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_templates";
create policy bsb_tenant_scope_update on "better_supabase"."document_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."document_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."document_text_blocks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_select on "better_supabase"."document_text_blocks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_insert on "better_supabase"."document_text_blocks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_update on "better_supabase"."document_text_blocks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_delete on "better_supabase"."document_text_blocks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rendered_documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_select on "better_supabase"."rendered_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("tenant_id", "document_type", "document_id") end))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_insert on "better_supabase"."rendered_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_update on "better_supabase"."rendered_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_delete on "better_supabase"."rendered_documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.document-templates.api: entry points for the Data API.
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

create or replace function "api"."document_address"(address jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_address"($1) $$;
revoke execute on function "api"."document_address"(jsonb) from public, anon;
grant execute on function "api"."document_address"(jsonb) to authenticated, service_role;

create or replace function "api"."document_entity"(tenant uuid, legal_entity uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_entity"($1, $2) $$;
revoke execute on function "api"."document_entity"(uuid, uuid) from public, anon;
grant execute on function "api"."document_entity"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."document_party"(tenant uuid, company_id text, contact_id text, buyer jsonb default null, email text default null, address jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_party"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."document_party"(uuid, text, text, jsonb, text, jsonb) from public, anon;
grant execute on function "api"."document_party"(uuid, text, text, jsonb, text, jsonb) to authenticated, service_role;

create or replace function "api"."document_tax_summary"(lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_tax_summary"($1) $$;
revoke execute on function "api"."document_tax_summary"(jsonb) from public, anon;
grant execute on function "api"."document_tax_summary"(jsonb) to authenticated, service_role;

create or replace function "api"."document_visible"(tenant uuid, document_type text, document_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_visible"($1, $2, $3) $$;
revoke execute on function "api"."document_visible"(uuid, text, uuid) from public, anon;
grant execute on function "api"."document_visible"(uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."document_variables"(tenant uuid, document_type text, document_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_variables"($1, $2, $3) $$;
revoke execute on function "api"."document_variables"(uuid, text, uuid) from public, anon;
grant execute on function "api"."document_variables"(uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."document_template_contract"(document_type text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_template_contract"($1) $$;
revoke execute on function "api"."document_template_contract"(text) from public, anon;
grant execute on function "api"."document_template_contract"(text) to authenticated, service_role;

create or replace function "api"."validate_document_template"(document_type text, body text, text_block boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."validate_document_template"($1, $2, $3) $$;
revoke execute on function "api"."validate_document_template"(text, text, boolean) from public, anon;
grant execute on function "api"."validate_document_template"(text, text, boolean) to authenticated, service_role;

create or replace function "api"."document_slot_rank"(entity uuid, wanted_entity uuid, language text, wanted_language text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_slot_rank"($1, $2, $3, $4) $$;
revoke execute on function "api"."document_slot_rank"(uuid, uuid, text, text) from public, anon;
grant execute on function "api"."document_slot_rank"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "api"."save_document_template"(tenant uuid, document_type text, body text, language text default null, name text default 'default', legal_entity_id uuid default null, active boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_document_template"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."save_document_template"(uuid, text, text, text, text, uuid, boolean) from public, anon;
grant execute on function "api"."save_document_template"(uuid, text, text, text, text, uuid, boolean) to authenticated, service_role;

create or replace function "api"."set_document_template_active"(template_id uuid, active boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_document_template_active"($1, $2) $$;
revoke execute on function "api"."set_document_template_active"(uuid, boolean) from public, anon;
grant execute on function "api"."set_document_template_active"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."get_document_template"(template_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_document_template"($1) $$;
revoke execute on function "api"."get_document_template"(uuid) from public, anon;
grant execute on function "api"."get_document_template"(uuid) to authenticated, service_role;

create or replace function "api"."list_document_templates"(tenant uuid, document_type text default null, legal_entity_id uuid default null, active_only boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_document_templates"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_document_templates"(uuid, text, uuid, boolean) from public, anon;
grant execute on function "api"."list_document_templates"(uuid, text, uuid, boolean) to authenticated, service_role;

create or replace function "api"."save_document_text_block"(tenant uuid, key text, body text, language text default null, legal_entity_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_document_text_block"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_document_text_block"(uuid, text, text, text, uuid) from public, anon;
grant execute on function "api"."save_document_text_block"(uuid, text, text, text, uuid) to authenticated, service_role;

create or replace function "api"."list_document_text_blocks"(tenant uuid, key text default null, legal_entity_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_document_text_blocks"($1, $2, $3) $$;
revoke execute on function "api"."list_document_text_blocks"(uuid, text, uuid) from public, anon;
grant execute on function "api"."list_document_text_blocks"(uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."resolve_document_template"(tenant uuid, document_type text, legal_entity_id uuid default null, language text default null, name text default 'default')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_document_template"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."resolve_document_template"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "api"."resolve_document_template"(uuid, text, uuid, text, text) to authenticated, service_role;

create or replace function "api"."resolve_document_blocks"(tenant uuid, keys text[], legal_entity_id uuid default null, language text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_document_blocks"($1, $2, $3, $4) $$;
revoke execute on function "api"."resolve_document_blocks"(uuid, text[], uuid, text) from public, anon;
grant execute on function "api"."resolve_document_blocks"(uuid, text[], uuid, text) to authenticated, service_role;

create or replace function "api"."document_render_live"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_render_live"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."document_render_live"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "api"."document_render_live"(uuid, text, uuid, text, text) to authenticated, service_role;

create or replace function "api"."render_document"(tenant uuid, document_type text, document_id uuid, language text default null, fresh boolean default false, template_name text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."render_document"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."render_document"(uuid, text, uuid, text, boolean, text) from public, anon;
grant execute on function "api"."render_document"(uuid, text, uuid, text, boolean, text) to authenticated, service_role;

create or replace function "api"."freeze_document"(tenant uuid, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."freeze_document"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."freeze_document"(uuid, text, uuid, text, text) from public, anon;
grant execute on function "api"."freeze_document"(uuid, text, uuid, text, text) to authenticated, service_role;

create or replace function "api"."import_document_template"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_document_template"($1, $2, $3) $$;
revoke execute on function "api"."import_document_template"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_document_template"(uuid, jsonb, text) to service_role;

create or replace function "api"."import_document_text_block"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_document_text_block"($1, $2, $3) $$;
revoke execute on function "api"."import_document_text_block"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_document_text_block"(uuid, jsonb, text) to service_role;

create or replace function "api"."document_template_updated_at"(subject_id text)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_template_updated_at"($1) $$;
revoke execute on function "api"."document_template_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."document_template_updated_at"(text) to service_role;

create or replace function "api"."document_text_block_updated_at"(subject_id text)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_text_block_updated_at"($1) $$;
revoke execute on function "api"."document_text_block_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."document_text_block_updated_at"(text) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_163_document_templates.sql
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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block document-templates@1 managed
-- @bsb-hash sha256:cf6702235cc7e329b64e95562bffac5a34ebd6d13d0e4b0c2d987152fe6477d5
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
-- better_supabase.document_templates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."document_templates" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."document_templates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."document_templates" add column if not exists "legal_entity_id" uuid;
alter table "better_supabase"."document_templates" add column if not exists "document_type" text check ("document_type" in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement'));
alter table "better_supabase"."document_templates" add column if not exists "language" text check ("language" is null or "language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$');
alter table "better_supabase"."document_templates" add column if not exists "name" text not null default 'default' check ("name" ~ '^[a-z][a-z0-9_-]{0,63}$');
alter table "better_supabase"."document_templates" add column if not exists "body" text check (length(btrim("body")) > 0 and length("body") <= 200000);
alter table "better_supabase"."document_templates" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "better_supabase"."document_templates" add column if not exists "active" boolean not null default true;
alter table "better_supabase"."document_templates" add column if not exists "created_by" uuid references auth.users (id) on delete set null default auth.uid();
alter table "better_supabase"."document_templates" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."document_templates" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "document_templates_lookup_idx" on "better_supabase"."document_templates" ("tenant_id", "document_type", "name") where "active";
create index if not exists "document_templates_entity_idx" on "better_supabase"."document_templates" ("tenant_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_templates_created_by_idx" on "better_supabase"."document_templates" ("created_by") where "created_by" is not null;
alter table "better_supabase"."document_templates" enable row level security;
grant select on "better_supabase"."document_templates" to authenticated;
grant all on "better_supabase"."document_templates" to service_role;
drop policy if exists bsb_document_templates_read on "better_supabase"."document_templates";
create policy bsb_document_templates_read on "better_supabase"."document_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- Reusable texts, read in a template as texts.<key>.
-- better_supabase.document_text_blocks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."document_text_blocks" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."document_text_blocks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."document_text_blocks" add column if not exists "legal_entity_id" uuid;
alter table "better_supabase"."document_text_blocks" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_]{0,63}$');
alter table "better_supabase"."document_text_blocks" add column if not exists "language" text check ("language" is null or "language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$');
alter table "better_supabase"."document_text_blocks" add column if not exists "body" text check (length(btrim("body")) > 0 and length("body") <= 200000);
alter table "better_supabase"."document_text_blocks" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "better_supabase"."document_text_blocks" add column if not exists "created_by" uuid references auth.users (id) on delete set null default auth.uid();
alter table "better_supabase"."document_text_blocks" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."document_text_blocks" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "document_text_blocks_entity_idx" on "better_supabase"."document_text_blocks" ("tenant_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_text_blocks_created_by_idx" on "better_supabase"."document_text_blocks" ("created_by") where "created_by" is not null;
alter table "better_supabase"."document_text_blocks" enable row level security;
grant select on "better_supabase"."document_text_blocks" to authenticated;
grant all on "better_supabase"."document_text_blocks" to service_role;
drop policy if exists bsb_document_text_blocks_read on "better_supabase"."document_text_blocks";
create policy bsb_document_text_blocks_read on "better_supabase"."document_text_blocks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- What a document looked like when it was frozen: its variables, the template
-- and the text blocks it used. A snapshot never changes. The template column
-- keeps the body, so deleting or editing the template leaves it as it was.
-- better_supabase.rendered_documents is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."rendered_documents" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."rendered_documents" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."rendered_documents" add column if not exists "document_type" text check ("document_type" in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement'));
alter table "better_supabase"."rendered_documents" add column if not exists "document_id" uuid;
alter table "better_supabase"."rendered_documents" add column if not exists "language" text;
alter table "better_supabase"."rendered_documents" add column if not exists "legal_entity_id" uuid;
alter table "better_supabase"."rendered_documents" add column if not exists "contract_version" integer;
alter table "better_supabase"."rendered_documents" add column if not exists "template_id" uuid;
alter table "better_supabase"."rendered_documents" add column if not exists "template_version" integer;
alter table "better_supabase"."rendered_documents" add column if not exists "template" jsonb;
alter table "better_supabase"."rendered_documents" add column if not exists "blocks" jsonb not null default '{}'::jsonb check (jsonb_typeof("blocks") = 'object');
alter table "better_supabase"."rendered_documents" add column if not exists "variables" jsonb check (jsonb_typeof("variables") = 'object');
alter table "better_supabase"."rendered_documents" add column if not exists "created_by" uuid references auth.users (id) on delete set null default auth.uid();
alter table "better_supabase"."rendered_documents" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "rendered_documents_created_by_idx" on "better_supabase"."rendered_documents" ("created_by") where "created_by" is not null;
alter table "better_supabase"."rendered_documents" enable row level security;
grant select on "better_supabase"."rendered_documents" to authenticated;
grant all on "better_supabase"."rendered_documents" to service_role;
-- A snapshot shows to someone who can read the document it froze; a statement
-- has no row of its own, so it shows to the template managers.
drop policy if exists bsb_rendered_documents_read on "better_supabase"."rendered_documents";
create policy bsb_rendered_documents_read on "better_supabase"."rendered_documents"
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
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."document_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_templates";
create policy bsb_tenant_scope_update on "better_supabase"."document_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."document_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."document_text_blocks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_select on "better_supabase"."document_text_blocks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_insert on "better_supabase"."document_text_blocks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_update on "better_supabase"."document_text_blocks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_delete on "better_supabase"."document_text_blocks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rendered_documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_select on "better_supabase"."rendered_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "tenant_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("tenant_id", "document_type", "document_id") end))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_insert on "better_supabase"."rendered_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_update on "better_supabase"."rendered_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_delete on "better_supabase"."rendered_documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_163_document_templates.sql
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

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_163_document_templates.sql
-- better-supabase module: document-templates
-- @bsb-block document-templates@1 managed
-- @bsb-hash sha256:73e591d2afeceda23a45717018dfa5667214098372d92920d4bf0e452567b240
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
  "org_id" uuid not null,
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
  foreign key ("org_id", "legal_entity_id") references "better_supabase"."legal_entities" ("org_id", "id") on delete restrict
);
-- One template per slot.
create unique index if not exists "document_templates_slot_idx" on "better_supabase"."document_templates" ("org_id", "document_type", "name", coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid), coalesce("language", ''));
create index if not exists "document_templates_lookup_idx" on "better_supabase"."document_templates" ("org_id", "document_type", "name") where "active";
create index if not exists "document_templates_entity_idx" on "better_supabase"."document_templates" ("org_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_templates_created_by_idx" on "better_supabase"."document_templates" ("created_by") where "created_by" is not null;
alter table "better_supabase"."document_templates" enable row level security;
revoke all on "better_supabase"."document_templates" from public, anon, authenticated;
grant select on "better_supabase"."document_templates" to authenticated;
grant all on "better_supabase"."document_templates" to service_role;
drop policy if exists document_templates_read on "better_supabase"."document_templates";
create policy document_templates_read on "better_supabase"."document_templates"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- Reusable texts, read in a template as texts.<key>.
create table if not exists "better_supabase"."document_text_blocks" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "legal_entity_id" uuid,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,63}$'),
  "language" text check ("language" is null or "language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  "body" text not null check (length(btrim("body")) > 0 and length("body") <= 200000),
  "version" integer not null default 1 check ("version" >= 1),
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("org_id", "legal_entity_id") references "better_supabase"."legal_entities" ("org_id", "id") on delete restrict
);
create unique index if not exists "document_text_blocks_slot_idx" on "better_supabase"."document_text_blocks" ("org_id", "key", coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid), coalesce("language", ''));
create index if not exists "document_text_blocks_entity_idx" on "better_supabase"."document_text_blocks" ("org_id", "legal_entity_id") where "legal_entity_id" is not null;
create index if not exists "document_text_blocks_created_by_idx" on "better_supabase"."document_text_blocks" ("created_by") where "created_by" is not null;
alter table "better_supabase"."document_text_blocks" enable row level security;
revoke all on "better_supabase"."document_text_blocks" from public, anon, authenticated;
grant select on "better_supabase"."document_text_blocks" to authenticated;
grant all on "better_supabase"."document_text_blocks" to service_role;
drop policy if exists document_text_blocks_read on "better_supabase"."document_text_blocks";
create policy document_text_blocks_read on "better_supabase"."document_text_blocks"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('document_templates.read')));

-- What a document looked like when it was frozen: its variables, the template
-- and the text blocks it used. A snapshot never changes. The template column
-- keeps the body, so deleting or editing the template leaves it as it was.
create table if not exists "better_supabase"."rendered_documents" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
  unique ("org_id", "document_type", "document_id")
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
  using ("org_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "org_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("org_id", "document_type", "document_id") end));


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
    where t."org_id" = save_document_template.tenant
      and t."document_type" = save_document_template.document_type
      and t."name" = v_name
      and t."legal_entity_id" is not distinct from save_document_template.legal_entity_id
      and t."language" is not distinct from v_language;
  if found then
    v_changed := v_row."body" <> save_document_template.body;
    if not v_changed and v_row."active" = v_active then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
    insert into "better_supabase"."document_templates" ("org_id", "legal_entity_id", "document_type", "language", "name", "body", "active")
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if v_row."active" is distinct from coalesce(set_document_template_active.active, true) then
    update "better_supabase"."document_templates" t set "active" = coalesce(set_document_template_active.active, true), "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organizationId', t."org_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") order by t."document_type", t."name", t."legal_entity_id" nulls first, t."language" nulls first), '[]'::jsonb)
  from "better_supabase"."document_templates" t
  where t."org_id" = list_document_templates.tenant
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
    where b."org_id" = save_document_text_block.tenant
      and b."key" = save_document_text_block.key
      and b."legal_entity_id" is not distinct from save_document_text_block.legal_entity_id
      and b."language" is not distinct from v_language;
  if found then
    if v_row."body" = save_document_text_block.body then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'key', v_row."key", 'language', v_row."language", 'body', v_row."body", 'version', v_row."version", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    update "better_supabase"."document_text_blocks" b set "body" = save_document_text_block.body, "version" = b."version" + 1, "updated_at" = now()
    where b."id" = v_row."id"
    returning * into v_row;
    null;
  else
    insert into "better_supabase"."document_text_blocks" ("org_id", "legal_entity_id", "key", "language", "body")
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'key', v_row."key", 'language', v_row."language", 'body', v_row."body", 'version', v_row."version", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  select coalesce(jsonb_agg(jsonb_build_object('id', b."id", 'organizationId', b."org_id", 'legalEntityId', b."legal_entity_id", 'key', b."key", 'language', b."language", 'body', b."body", 'version', b."version", 'createdAt', b."created_at", 'updatedAt', b."updated_at") order by b."key", b."legal_entity_id" nulls first, b."language" nulls first), '[]'::jsonb)
  from "better_supabase"."document_text_blocks" b
  where b."org_id" = list_document_text_blocks.tenant
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
  where t."org_id" = resolve_document_template.tenant
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
    where b."org_id" = resolve_document_blocks.tenant
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
      where s."org_id" = render_document.tenant
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
    where s."org_id" = document_freeze.tenant
      and s."document_type" = document_freeze.document_type
      and s."document_id" = document_freeze.document_id;
  if found then
    return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
  end if;
  v_live := "better_supabase"."document_render_live"(document_freeze.tenant, document_freeze.document_type, document_freeze.document_id, document_freeze.language, document_freeze.template_name);
  insert into "better_supabase"."rendered_documents" ("org_id", "document_type", "document_id", "language", "legal_entity_id", "contract_version", "template_id", "template_version", "template", "blocks", "variables")
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
      where x."org_id" = v_tenant and x."code" = v_data ->> 'legalEntity';
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
      where x."org_id" = v_tenant and x."code" = v_data ->> 'legalEntity';
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
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
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
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."document_templates" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_templates";
create policy bsb_tenant_scope_update on "better_supabase"."document_templates" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."document_templates" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."document_text_blocks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_select on "better_supabase"."document_text_blocks" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('document_templates.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_insert on "better_supabase"."document_text_blocks" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_update on "better_supabase"."document_text_blocks" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_text_blocks";
create policy bsb_tenant_scope_delete on "better_supabase"."document_text_blocks" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rendered_documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_select on "better_supabase"."rendered_documents" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('document_templates.read')) and (case when "document_type" = 'statement' then "org_id" in (select better_supabase.tenant_ids_with('document_templates.manage')) else "better_supabase"."document_visible"("org_id", "document_type", "document_id") end))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_insert on "better_supabase"."rendered_documents" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_update on "better_supabase"."rendered_documents" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rendered_documents";
create policy bsb_tenant_scope_delete on "better_supabase"."rendered_documents" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_163_document_templates.sql
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
