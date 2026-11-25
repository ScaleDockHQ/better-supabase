SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_account (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_account.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_account.item -> 'data';
  v_parent uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_accounting_account.item -> 'data') is distinct from 'object' then
    raise exception 'an account item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_parent := (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and case when nullif(v_data ->> 'parentId', '') is not null then y."id" = nullif(v_data ->> 'parentId', '')::uuid else y."code" = v_data ->> 'parentCode' end);
    if nullif(v_data ->> 'parentCode', '') is not null and v_parent is null then
      raise exception 'the parent account code isn''t an account of the organization; import parents first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    v_row := "better_supabase"."save_accounting_account"(v_tenant, v_data ->> 'code', v_data ->> 'name', v_data ->> 'type', nullif(v_data ->> 'subtype', ''),
      v_parent, nullif(v_data ->> 'currency', ''), coalesce((v_data ->> 'reconcilable')::boolean, false),
      import_accounting_account.subject_id::uuid, nullif(v_data ->> 'normalSide', ''), nullif(v_data ->> 'defaultTaxCodeId', '')::uuid,
      coalesce((v_data ->> 'active')::boolean, true));
  exception
    when invalid_text_representation then
      raise exception 'an account''s ids are uuids and its flags booleans' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_entry (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_entry.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_entry.item -> 'data';
  v_journal uuid;
  v_lines jsonb;
  v_debit numeric;
  v_credit numeric;
  v_row jsonb;
begin
  if jsonb_typeof(import_accounting_entry.item -> 'data') is distinct from 'object' then
    raise exception 'an entry item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_journal := (select y."id" from "better_supabase"."accounting_journals" y where y."tenant_id" = v_tenant
      and case when nullif(v_data ->> 'journalId', '') is not null then y."id" = nullif(v_data ->> 'journalId', '')::uuid else y."code" = v_data ->> 'journalCode' end);
    select jsonb_agg((e.value - 'accountCode') || jsonb_build_object('accountId', (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and case when nullif(e.value ->> 'accountId', '') is not null then y."id" = nullif(e.value ->> 'accountId', '')::uuid else y."code" = e.value ->> 'accountCode' end)) order by e.ordinality),
      coalesce(sum((coalesce(nullif(e.value ->> 'debit', ''), '0'))::numeric), 0),
      coalesce(sum((coalesce(nullif(e.value ->> 'credit', ''), '0'))::numeric), 0)
    into v_lines, v_debit, v_credit
    from jsonb_array_elements(v_data -> 'lines') with ordinality e;
  exception
    when invalid_text_representation then
      raise exception 'an entry''s ids are uuids and its amounts integers' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_journal is null then
    raise exception 'the journal isn''t a journal of the organization; import journals first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_lines) e where e.value ->> 'accountId' is null) then
    raise exception 'a line''s account isn''t an account of the organization; import accounts first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_debit <> v_credit then
    raise exception 'the lines don''t balance: debits and credits differ' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform "better_supabase"."ensure_import_periods"(v_tenant, (v_data ->> 'entryDate')::date,
    coalesce((import_accounting_entry.item -> 'options' -> 'fiscalYear' ->> 'startMonth')::integer, 1),
    coalesce((import_accounting_entry.item -> 'options' ->> 'closeHistorical')::boolean, false));
  v_row := "better_supabase"."save_accounting_entry"(v_journal, (v_data ->> 'entryDate')::date, v_lines, nullif(v_data ->> 'memo', ''), nullif(v_data ->> 'reference', ''),
    null, null, import_accounting_entry.subject_id::uuid);
  if coalesce((v_data ->> 'post')::boolean, true) then
    v_row := "better_supabase"."post_accounting_entry"((v_row ->> 'id')::uuid);
  end if;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_journal (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_journal.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_journal.item -> 'data';
  v_default uuid;
  v_contra uuid;
  v_bank uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_accounting_journal.item -> 'data') is distinct from 'object' then
    raise exception 'a journal item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_default := (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and case when nullif(v_data ->> 'defaultAccountId', '') is not null then y."id" = nullif(v_data ->> 'defaultAccountId', '')::uuid else y."code" = v_data ->> 'defaultAccountCode' end);
    v_contra := (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and case when nullif(v_data ->> 'contraAccountId', '') is not null then y."id" = nullif(v_data ->> 'contraAccountId', '')::uuid else y."code" = v_data ->> 'contraAccountCode' end);
    v_bank := (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and case when nullif(v_data ->> 'bankAccountId', '') is not null then y."id" = nullif(v_data ->> 'bankAccountId', '')::uuid else y."code" = v_data ->> 'bankAccountCode' end);
  exception
    when invalid_text_representation then
      raise exception 'a journal''s account ids are uuids' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if (nullif(v_data ->> 'defaultAccountCode', '') is not null and v_default is null)
    or (nullif(v_data ->> 'contraAccountCode', '') is not null and v_contra is null)
    or (nullif(v_data ->> 'bankAccountCode', '') is not null and v_bank is null) then
    raise exception 'an account code of the journal isn''t an account of the organization; import accounts first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."save_accounting_journal"(v_tenant, v_data ->> 'code', v_data ->> 'name', v_data ->> 'type', v_default,
    nullif(v_data ->> 'currency', ''), import_accounting_journal.subject_id::uuid, v_contra, v_bank);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_opening_balance (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_opening_balance.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_opening_balance.item -> 'data';
  v_account uuid;
begin
  if jsonb_typeof(import_accounting_opening_balance.item -> 'data') is distinct from 'object' then
    raise exception 'an opening balance item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'fiscalYear', '') !~ '^[0-9]{4}$' or coalesce(v_data ->> 'amount', '') !~ '^-?[0-9]{1,18}$' then
    raise exception 'an opening balance needs a fiscalYear and an integer amount' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_account := (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and case when nullif(v_data ->> 'accountId', '') is not null then y."id" = nullif(v_data ->> 'accountId', '')::uuid else y."code" = v_data ->> 'accountCode' end);
    return jsonb_build_object('subjectId', "better_supabase"."accounting_opening_write"(v_tenant, (v_data ->> 'fiscalYear')::integer, v_account,
      nullif(v_data ->> 'partyId', '')::uuid, (v_data ->> 'amount')::bigint));
  exception
    when invalid_text_representation then
      raise exception 'an opening balance''s ids are uuids' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_contact_method (
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
  v_data jsonb := import_contact_method.item -> 'data';
  v_party uuid := nullif(coalesce(import_contact_method.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_kind text := coalesce(nullif(v_data ->> 'partyKind', ''), 'person');
  v_channel text := nullif(v_data ->> 'channel', '');
  v_address text := nullif(btrim(v_data ->> 'address'), '');
  v_id uuid;
  v_updated timestamptz;
begin
  if v_channel in ('email') then
    v_address := nullif(lower(v_address), '');
  elsif v_channel in ('phone', 'mobile', 'fax', 'whatsapp') then
    v_address := nullif(better_supabase.normalize_phone(v_address, v_data ->> 'region'), '');
  end if;
  if v_party is null or v_kind not in ('person', 'company') or v_channel not in ('email', 'phone', 'mobile', 'fax', 'whatsapp') or v_address is null then
    raise exception 'a contact method needs a party, a channel and an address' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (exists (select 1 from "better_supabase"."companies" p where p."id" = v_party and p."tenant_id" = (import_contact_method.item ->> 'tenant')::uuid) or exists (select 1 from "better_supabase"."people" p where p."id" = v_party and p."tenant_id" = (import_contact_method.item ->> 'tenant')::uuid)) then
    raise exception 'the party isn''t one of this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select x."id", x."updated_at" into v_id, v_updated from "better_supabase"."party_channels" x
  where x."tenant_id" = (import_contact_method.item ->> 'tenant')::uuid
    and x."party_id" = v_party and x."channel" = v_channel and x."address" = v_address
    and x."label" is not distinct from nullif(btrim(v_data ->> 'label'), '')
    and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, false);
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into "better_supabase"."party_channels" ("tenant_id", "party_id", "party_kind", "channel", "label", "address", "is_primary")
  values ((import_contact_method.item ->> 'tenant')::uuid, v_party, v_kind, v_channel, nullif(btrim(v_data ->> 'label'), ''), v_address, coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict ("tenant_id", "party_id", "channel", "address") do update
    set "label" = excluded."label", "is_primary" = excluded."is_primary", "updated_at" = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party_bank_account (
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
  v_data jsonb := import_party_bank_account.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_bank_account.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_iban text := upper(regexp_replace(coalesce(v_data ->> 'iban', ''), '\s', '', 'g'));
  v_id uuid;
  v_updated timestamptz;
begin
  if v_party is null or not better_supabase.validate_iban(v_iban) then
    raise exception 'a bank account needs a party and a valid IBAN' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (exists (select 1 from "better_supabase"."companies" p where p."id" = v_party and p."tenant_id" = (import_party_bank_account.item ->> 'tenant')::uuid) or exists (select 1 from "better_supabase"."people" p where p."id" = v_party and p."tenant_id" = (import_party_bank_account.item ->> 'tenant')::uuid)) then
    raise exception 'the party isn''t one of this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select x."id", x."updated_at" into v_id, v_updated from "better_supabase"."party_bank_accounts" x
  where x."tenant_id" = (import_party_bank_account.item ->> 'tenant')::uuid and x."iban" = v_iban
    and x."bic" is not distinct from nullif(upper(btrim(v_data ->> 'bic')), '')
    and x."holder" is not distinct from nullif(btrim(v_data ->> 'holder'), '')
    and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, x."is_primary");
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into "better_supabase"."party_bank_accounts" ("tenant_id", "party_id", "iban", "bic", "holder", "is_primary")
  values ((import_party_bank_account.item ->> 'tenant')::uuid, v_party, v_iban,
    nullif(upper(btrim(v_data ->> 'bic')), ''), nullif(btrim(v_data ->> 'holder'), ''), coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict ("tenant_id", "iban") do update
    set "bic" = excluded."bic", "holder" = excluded."holder",
      "is_primary" = coalesce((v_data ->> 'isPrimary')::boolean, "better_supabase"."party_bank_accounts"."is_primary"),
      "updated_at" = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party_contact (
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
  v_data jsonb := import_party_contact.item -> 'data';
  v_company uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'company', v_data ->> 'companyId'), '')::uuid;
  v_person uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'person', v_data ->> 'personId'), '')::uuid;
  v_primary boolean := coalesce((v_data ->> 'isPrimary')::boolean, false);
begin
  if v_company is null or v_person is null then
    raise exception 'a party contact needs a company and a person' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (exists (select 1 from "better_supabase"."companies" p where p."id" = v_company and p."tenant_id" = (import_party_contact.item ->> 'tenant')::uuid)) then
    raise exception 'the party isn''t one of this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (exists (select 1 from "better_supabase"."people" p where p."id" = v_person and p."tenant_id" = (import_party_contact.item ->> 'tenant')::uuid)) then
    raise exception 'the party isn''t one of this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."company_people" x
    where x."company_id" = v_company and x."person_id" = v_person
      and x."is_primary" is not distinct from v_primary
      and x."role" is not distinct from nullif(btrim(v_data ->> 'role'), '')
  ) then
    return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt',
      (select x."created_at" from "better_supabase"."company_people" x where x."company_id" = v_company and x."person_id" = v_person));
  end if;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "is_primary", "role")
  values ((import_party_contact.item ->> 'tenant')::uuid, v_company, v_person, v_primary, nullif(btrim(v_data ->> 'role'), ''))
  on conflict ("company_id", "person_id") do update
    set "is_primary" = excluded."is_primary", "role" = nullif(btrim(v_data ->> 'role'), '');
  return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt', now());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_party_location (
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
  v_data jsonb := import_party_location.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_location.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_id uuid;
  v_updated timestamptz;
  v_same boolean;
begin
  if v_party is null then
    raise exception 'a location needs a party' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (exists (select 1 from "better_supabase"."companies" p where p."id" = v_party and p."tenant_id" = (import_party_location.item ->> 'tenant')::uuid) or exists (select 1 from "better_supabase"."people" p where p."id" = v_party and p."tenant_id" = (import_party_location.item ->> 'tenant')::uuid)) then
    raise exception 'the party isn''t one of this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_party_location.subject_id is not null then
    select x."id", x."updated_at", x."party_id" is not distinct from v_party and x."kind" is not distinct from coalesce(nullif(v_data ->> 'kind', ''), 'other') and x."line1" is not distinct from nullif(btrim(v_data ->> 'line1'), '') and x."line2" is not distinct from nullif(btrim(v_data ->> 'line2'), '') and x."postal_code" is not distinct from nullif(btrim(v_data ->> 'postalCode'), '') and x."city" is not distinct from nullif(btrim(v_data ->> 'city'), '') and x."country" is not distinct from nullif(btrim(v_data ->> 'country'), '') and x."latitude" is not distinct from nullif(v_data ->> 'latitude', '')::double precision and x."longitude" is not distinct from nullif(v_data ->> 'longitude', '')::double precision and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, false) into v_id, v_updated, v_same
    from "better_supabase"."party_locations" x
    where x."id" = import_party_location.subject_id::uuid and x."tenant_id" = (import_party_location.item ->> 'tenant')::uuid;
    if v_id is not null and v_same then
      return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
    end if;
    update "better_supabase"."party_locations" x set "party_id" = v_party, "kind" = coalesce(nullif(v_data ->> 'kind', ''), 'other'), "line1" = nullif(btrim(v_data ->> 'line1'), ''), "line2" = nullif(btrim(v_data ->> 'line2'), ''), "postal_code" = nullif(btrim(v_data ->> 'postalCode'), ''), "city" = nullif(btrim(v_data ->> 'city'), ''), "country" = nullif(btrim(v_data ->> 'country'), ''), "latitude" = nullif(v_data ->> 'latitude', '')::double precision, "longitude" = nullif(v_data ->> 'longitude', '')::double precision, "is_primary" = coalesce((v_data ->> 'isPrimary')::boolean, false), "updated_at" = now()
    where x."id" = import_party_location.subject_id::uuid
    returning x."id", x."updated_at" into v_id, v_updated;
  end if;
  if v_id is null then
    insert into "better_supabase"."party_locations" ("tenant_id", "party_id", "kind", "line1", "line2", "postal_code", "city", "country", "latitude", "longitude", "is_primary")
    values ((import_party_location.item ->> 'tenant')::uuid, v_party, coalesce(nullif(v_data ->> 'kind', ''), 'other'), nullif(btrim(v_data ->> 'line1'), ''), nullif(btrim(v_data ->> 'line2'), ''), nullif(btrim(v_data ->> 'postalCode'), ''), nullif(btrim(v_data ->> 'city'), ''), nullif(btrim(v_data ->> 'country'), ''), nullif(v_data ->> 'latitude', '')::double precision, nullif(v_data ->> 'longitude', '')::double precision, coalesce((v_data ->> 'isPrimary')::boolean, false))
    returning "id", "updated_at" into v_id, v_updated;
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$function$;
