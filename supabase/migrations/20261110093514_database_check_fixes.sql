SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.app_organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    invited_by text,
    created_at timestamp with time zone,
    expires_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.invite') then
    raise exception 'Not allowed to list invitations' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  return query
  select i.id, i.email, coalesce(r.key, i.role), coalesce(p.full_name, p.email), i.created_at, i.expires_at
  from better_supabase.invitations i
  left join better_supabase.roles r on r.id::text = i.role
  left join better_supabase.profiles p on p.id = i.invited_by
  where i.tenant_id = organization
    and i.accepted_at is null and i.declined_at is null and i.revoked_at is null
    and i.expires_at >= now()
  order by i.created_at desc;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id     uuid,
    role        text,
    full_name   text,
    email       text,
    avatar_url  text,
    avatar_path text,
    joined_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- The service role lists any organization's members (the workflow tick
  -- route looks up the owner a schedule runs as).
  if not ((select auth.role()) = 'service_role'
    or better_supabase.member_can((select auth.uid()), organization, 'members.read')) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m.user_id, r.key, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, p.avatar_path, m.created_at
  from public.memberships m
  join better_supabase.roles r on r.id = m.role
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by array_position(array['member', 'admin', 'owner'], r.key) desc nulls last, coalesce(p.full_name, u.email::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_import_periods (
  tenant           uuid,
  entry_date       date,
  start_month      integer,
  close_historical boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_month integer := least(greatest(coalesce(ensure_import_periods.start_month, 1), 1), 12);
  v_year integer := extract(year from ensure_import_periods.entry_date)::integer;
  v_start date;
  v_index integer;
begin
  if extract(month from ensure_import_periods.entry_date) < v_month then
    v_year := v_year - 1;
  end if;
  v_start := make_date(v_year, v_month, 1);
  if not exists (select 1 from "better_supabase"."accounting_periods" y where y."tenant_id" = ensure_import_periods.tenant and y."fiscal_year" = v_year) then
    for v_index in 0..11 loop
      insert into "better_supabase"."accounting_periods" ("tenant_id", "fiscal_year", "number", "starts_on", "ends_on")
      values (ensure_import_periods.tenant, v_year, v_index + 1, (v_start + make_interval(months => v_index))::date,
        (v_start + make_interval(months => v_index + 1))::date - 1);
    end loop;
  end if;
  if ensure_import_periods.close_historical then
    update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now()
    where y."tenant_id" = ensure_import_periods.tenant and y."fiscal_year" < v_year and y."status" = 'open';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_ensure_ref (
  tenant   uuid,
  kind     text,
  key      text,
  defaults jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_product (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := import_product.item -> 'data';
  v_tenant uuid := (import_product.item ->> 'tenant')::uuid;
  v_raw text := coalesce(v_data ->> 'name', v_data ->> 'title', '');
  v_name text;
  v_slug text;
  v_sku text := nullif(btrim(v_data ->> 'sku'), '');
  v_price bigint;
  v_id uuid := nullif(import_product.subject_id, '')::uuid;
  v_updated timestamptz;
  v_fallback boolean := coalesce((import_product.item -> 'options' ->> 'priceFallback')::boolean, false);
begin
  if length(regexp_replace(v_raw, '[[:cntrl:][:space:]]', '', 'g')) * 2 < length(regexp_replace(coalesce(v_raw, ''), '[[:space:]]', '', 'g')) then
    raise exception 'a product name is mostly control characters' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_name := btrim(regexp_replace(regexp_replace(v_raw, '[[:cntrl:]]', '', 'g'), U&'[\+00E000-\+00F8FF]', '', 'g'));
  if v_name is null or length(v_name) = 0 then
    raise exception 'a product needs a name' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_price := coalesce(
    nullif(v_data ->> 'price', '')::bigint,
    nullif(v_data ->> 'listPrice', '')::bigint,
    case when v_fallback then round(nullif(v_data ->> 'lastPurchasePrice', '')::numeric * coalesce(nullif(v_data ->> 'markup', '')::numeric, 1))::bigint end);
  v_slug := trim(both '-' from lower(regexp_replace(coalesce(nullif(v_data ->> 'slug', ''), v_name), '[^a-zA-Z0-9]+', '-', 'g')));
  if v_id is not null and exists (
    select 1 from "better_supabase"."products" x
    where x."id" = v_id and x."tenant_id" = v_tenant and x."title" is not distinct from v_name
      and x."slug" is not distinct from v_slug
      
  ) and (v_sku is null or exists (
    select 1 from "better_supabase"."product_variants" y where y."product_id" = v_id and y."sku" is not distinct from v_sku
  )) then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', (select x."updated_at" from "better_supabase"."products" x where x."id" = v_id));
  end if;
  if v_sku is not null and exists (
    select 1 from "better_supabase"."product_variants" y where y."tenant_id" = v_tenant and y."sku" = v_sku and y."product_id" is distinct from v_id
  ) then
    raise exception 'a sku is already used by another product' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."products" x where x."tenant_id" = v_tenant and x."slug" = v_slug and x."id" is distinct from v_id) then
    v_slug := left(v_slug, 40) || '-' || left(coalesce(import_product.item ->> 'key', 'item'), 8);
  end if;
  if v_id is null then
    insert into "better_supabase"."products" ("tenant_id", "title", "slug", "manufacturer", "model", "tax_code")
    values (v_tenant, v_name, v_slug, nullif(btrim(v_data ->> 'manufacturer'), ''), nullif(btrim(v_data ->> 'model'), ''), nullif(coalesce(import_product.item -> 'resolved' ->> 'tax', v_data ->> 'taxCode'), ''))
    returning "id", "updated_at" into v_id, v_updated;
  else
    update "better_supabase"."products" x set "title" = v_name, "slug" = v_slug, "updated_at" = now(), "manufacturer" = coalesce(nullif(btrim(v_data ->> 'manufacturer'), ''), x."manufacturer"), "model" = coalesce(nullif(btrim(v_data ->> 'model'), ''), x."model"), "tax_code" = coalesce(nullif(coalesce(import_product.item -> 'resolved' ->> 'tax', v_data ->> 'taxCode'), ''), x."tax_code")
    where x."id" = v_id and x."tenant_id" = v_tenant
    returning x."updated_at" into v_updated;
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" y where y."product_id" = v_id) then
    insert into "better_supabase"."product_variants" ("tenant_id", "product_id", "sku", "barcode")
    values (v_tenant, v_id, coalesce(v_sku, v_slug), nullif(btrim(v_data ->> 'ean'), ''));
  elsif v_sku is not null then
    update "better_supabase"."product_variants" y set "sku" = v_sku, "barcode" = coalesce(nullif(btrim(v_data ->> 'ean'), ''), y."barcode")
    where y."id" = (select y2."id" from "better_supabase"."product_variants" y2 where y2."product_id" = v_id order by y2."created_at" limit 1);
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_import_source (
  id              text,
  label_key       text,
  description_key text,
  file_types      text[],
  entities        text[],
  docs_link       text   DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
  values (register_import_source.id, register_import_source.label_key, register_import_source.description_key,
    coalesce(register_import_source.file_types, '{}'), coalesce(register_import_source.entities, '{}'), register_import_source.docs_link)
  on conflict ("id") do update set
    "label_key" = excluded."label_key",
    "description_key" = excluded."description_key",
    "file_types" = excluded."file_types",
    "entities" = excluded."entities",
    "docs_link" = excluded."docs_link";
end;
$function$;
