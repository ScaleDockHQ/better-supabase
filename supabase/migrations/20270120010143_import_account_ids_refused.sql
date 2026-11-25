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
    if coalesce(nullif(v_data ->> 'parentId', ''), nullif(v_data ->> 'parentCode', '')) is not null and v_parent is null then
      raise exception 'the parent account isn''t an account of the organization; import parents first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
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
  if (coalesce(nullif(v_data ->> 'defaultAccountId', ''), nullif(v_data ->> 'defaultAccountCode', '')) is not null and v_default is null)
    or (coalesce(nullif(v_data ->> 'contraAccountId', ''), nullif(v_data ->> 'contraAccountCode', '')) is not null and v_contra is null)
    or (coalesce(nullif(v_data ->> 'bankAccountId', ''), nullif(v_data ->> 'bankAccountCode', '')) is not null and v_bank is null) then
    raise exception 'an account of the journal isn''t an account of the organization; import accounts first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."save_accounting_journal"(v_tenant, v_data ->> 'code', v_data ->> 'name', v_data ->> 'type', v_default,
    nullif(v_data ->> 'currency', ''), import_accounting_journal.subject_id::uuid, v_contra, v_bank);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$function$;
