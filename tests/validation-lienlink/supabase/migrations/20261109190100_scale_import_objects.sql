-- Objects the 0.58 scale and import modules added. The declarative sync was not run: the shadow database image did not start.

create or replace function better_supabase.validate_iban(value text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  compact text;
  moved text;
  rest integer := 0;
  i integer;
  piece text;
  j integer;
begin
  compact := upper(regexp_replace(coalesce(value, ''), '\s', '', 'g'));
  if compact !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then
    return false;
  end if;
  moved := substring(compact from 5) || substring(compact from 1 for 4);
  for i in 1 .. char_length(moved) loop
    piece := case
      when substring(moved from i for 1) between 'A' and 'Z'
        then (ascii(substring(moved from i for 1)) - 55)::text
      else substring(moved from i for 1)
    end;
    for j in 1 .. char_length(piece) loop
      rest := (rest * 10 + ascii(substring(piece from j for 1)) - 48) % 97;
    end loop;
  end loop;
  return rest = 1;
end;
$$;
revoke execute on function better_supabase.validate_iban(text) from public, anon;
grant execute on function better_supabase.validate_iban(text) to authenticated, service_role;

create or replace function better_supabase.normalize_phone(value text, region text default null)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when compact like '00%' then '+' || regexp_replace(substring(compact from 3), '\D', '', 'g')
    when compact like '+%' then '+' || regexp_replace(substring(compact from 2), '\D', '', 'g')
    when upper(region) = 'NL' and digits like '0%' then '+31' || substring(digits from 2)
    when upper(region) = 'DE' and digits like '0%' then '+49' || substring(digits from 2)
    when upper(region) = 'FR' and digits like '0%' then '+33' || substring(digits from 2)
    when upper(region) = 'GB' and digits like '0%' then '+44' || substring(digits from 2)
    when upper(region) = 'US' then '+1' || digits
    else digits
  end
  from (
    select regexp_replace(coalesce(value, ''), '[\s().-]', '', 'g') as compact
  ) raw,
  lateral (
    select case when compact like '00%' then substring(compact from 3) else compact end as body
  ) body,
  lateral (
    select regexp_replace(body, '\D', '', 'g') as digits
  ) digits
$$;
revoke execute on function better_supabase.normalize_phone(text, text) from public, anon;
grant execute on function better_supabase.normalize_phone(text, text) to authenticated, service_role;

create or replace function better_supabase.permission_bitset(all_keys text[], held text[])
returns text
language plpgsql
immutable
as $$
declare
  width integer := ceil(coalesce(cardinality(all_keys), 0) / 8.0);
  bytes bytea;
  i integer;
  slot integer;
  value integer;
begin
  if width < 1 then
    return '';
  end if;
  bytes := decode(repeat('00', width), 'hex');
  if held is null then
    return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
  end if;
  for i in 1 .. coalesce(cardinality(all_keys), 0) loop
    if all_keys[i] = any (held) then
      slot := (i - 1) / 8;
      value := get_byte(bytes, slot) | (1 << ((i - 1) % 8));
      bytes := set_byte(bytes, slot, value);
    end if;
  end loop;
  return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
end;
$$;

revoke execute on function better_supabase.permission_bitset(text[], text[]) from public, anon, authenticated;

create or replace function better_supabase.bootstrap_permissions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with keys as (
    select coalesce(array_agg(distinct key order by key), '{}'::text[]) as keys
    from better_supabase.member_organization_ids(null) as tenant(id),
      lateral unnest(better_supabase.member_permissions(auth.uid(), tenant.id)) as key
    where auth.uid() is not null
  )
  select case
    when auth.uid() is null then jsonb_build_object(
      'apiVersion', 1, 'form', 'compact', 'keys', '[]'::jsonb, 'tenants', '{}'::jsonb
    )
    else jsonb_build_object(
      'apiVersion', 1,
      'form', 'compact',
      'keys', to_jsonb(keys.keys),
      'tenants', coalesce((
        select jsonb_object_agg(
          tenant.id::text,
          better_supabase.permission_bitset(
            keys.keys,
            better_supabase.member_permissions(auth.uid(), tenant.id)
          )
        )
        from better_supabase.member_organization_ids(null) as tenant(id)
      ), '{}'::jsonb)
    )
  end
  from keys
$$;

revoke execute on function better_supabase.bootstrap_permissions() from public, anon;
grant execute on function better_supabase.bootstrap_permissions() to authenticated;

create table "better_supabase"."organization_profiles" (
  "tenant_id" uuid primary key,
  "vat_id" text,
  "registration_id" text,
  "default_rate" numeric,
  "currency" text,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."organization_profiles" enable row level security;
revoke all on "better_supabase"."organization_profiles" from public, anon, authenticated;
grant select on "better_supabase"."organization_profiles" to authenticated;
grant all on "better_supabase"."organization_profiles" to service_role;
create policy bsb_organization_profiles_read on "better_supabase"."organization_profiles"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create table "better_supabase"."organization_payment_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "iban" text not null,
  "bic" text,
  "holder" text,
  "label" text,
  "is_primary" boolean not null default false,
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "iban")
);
create unique index organization_payment_accounts_primary_idx
  on "better_supabase"."organization_payment_accounts" ("tenant_id") where "is_primary";
alter table "better_supabase"."organization_payment_accounts" enable row level security;
revoke all on "better_supabase"."organization_payment_accounts" from public, anon, authenticated;
grant select on "better_supabase"."organization_payment_accounts" to authenticated;
grant all on "better_supabase"."organization_payment_accounts" to service_role;
create policy bsb_organization_payment_accounts_read on "better_supabase"."organization_payment_accounts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- The organization's VAT, registration, default rate, currency and payment
-- accounts. An IBAN matches on a repeat import. A missing value leaves the
-- stored one, and the stored primary account stays unless an account says
-- isPrimary. A VAT number that is only a country prefix is skipped.
create or replace function "better_supabase"."import_organization_profile"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_organization_profile.item -> 'data';
  v_tenant uuid := (import_organization_profile.item ->> 'tenant')::uuid;
  v_vat text := nullif(upper(btrim(v_data ->> 'vatId')), '');
  v_warnings jsonb := '[]'::jsonb;
  v_account jsonb;
  v_iban text;
  v_primary boolean;
  v_id uuid;
  v_updated timestamptz;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'an organization profile needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_vat ~ '^[A-Z]{2}$' then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_VAT_PREFIX', 'message', 'a VAT number that is only a country prefix was skipped'));
    v_vat := null;
  end if;
  insert into "better_supabase"."organization_profiles" ("tenant_id") values (v_tenant) on conflict ("tenant_id") do nothing;
  if exists (
    select 1 from "better_supabase"."organization_profiles" x
    where x."tenant_id" = v_tenant
      and (v_vat is null or x."vat_id" is not distinct from v_vat)
      and (v_data ->> 'registrationId' is null or x."registration_id" is not distinct from nullif(btrim(v_data ->> 'registrationId'), ''))
      and (v_data ->> 'defaultRate' is null or x."default_rate" is not distinct from (v_data ->> 'defaultRate')::numeric)
      and (v_data ->> 'currency' is null or x."currency" is not distinct from nullif(btrim(v_data ->> 'currency'), ''))
  ) then
    v_updated := (select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id" = v_tenant);
  else
    update "better_supabase"."organization_profiles" x set
      "vat_id" = coalesce(v_vat, x."vat_id"),
      "registration_id" = coalesce(nullif(btrim(v_data ->> 'registrationId'), ''), x."registration_id"),
      "default_rate" = coalesce((v_data ->> 'defaultRate')::numeric, x."default_rate"),
      "currency" = coalesce(nullif(btrim(v_data ->> 'currency'), ''), x."currency"),
      "updated_at" = now()
    where x."tenant_id" = v_tenant
    returning x."updated_at" into v_updated;
  end if;
  if jsonb_typeof(v_data -> 'accounts') = 'array' then
    for v_account in select value from jsonb_array_elements(v_data -> 'accounts') loop
      v_iban := upper(regexp_replace(coalesce(v_account ->> 'iban', ''), '\s', '', 'g'));
      if not better_supabase.validate_iban(v_iban) then
        raise exception 'a payment account needs a valid IBAN' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
      v_primary := case when v_account ? 'isPrimary' then (v_account ->> 'isPrimary')::boolean else null end;
      select x."id" into v_id from "better_supabase"."organization_payment_accounts" x
      where x."tenant_id" = v_tenant and x."iban" = v_iban
        and x."bic" is not distinct from coalesce(nullif(upper(btrim(v_account ->> 'bic')), ''), x."bic")
        and x."holder" is not distinct from coalesce(nullif(btrim(v_account ->> 'holder'), ''), x."holder")
        and x."label" is not distinct from coalesce(nullif(btrim(v_account ->> 'label'), ''), x."label")
        and (v_primary is null or x."is_primary" = v_primary);
      if v_id is null then
        if v_primary is true then
          update "better_supabase"."organization_payment_accounts" x set "is_primary" = false where x."tenant_id" = v_tenant and x."iban" <> v_iban;
        end if;
        insert into "better_supabase"."organization_payment_accounts" ("tenant_id", "iban", "bic", "holder", "label", "is_primary")
        values (v_tenant, v_iban, nullif(upper(btrim(v_account ->> 'bic')), ''), nullif(btrim(v_account ->> 'holder'), ''),
          nullif(btrim(v_account ->> 'label'), ''), coalesce(v_primary, false))
        on conflict ("tenant_id", "iban") do update set
          "bic" = coalesce(excluded."bic", "better_supabase"."organization_payment_accounts"."bic"),
          "holder" = coalesce(excluded."holder", "better_supabase"."organization_payment_accounts"."holder"),
          "label" = coalesce(excluded."label", "better_supabase"."organization_payment_accounts"."label"),
          "is_primary" = case when v_primary is true then true else "better_supabase"."organization_payment_accounts"."is_primary" end,
          "updated_at" = now();
      end if;
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_tenant, 'updatedAt', coalesce(v_updated, now()), 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_organization_profile"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_organization_profile"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."organization_profile_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id"::text = organization_profile_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."organization_profile_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."organization_profile_updated_at"(text) to service_role;
