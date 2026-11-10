SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."bank_accounts"
  ADD COLUMN "holder" text;

ALTER TABLE "better_supabase"."bank_accounts"
  ADD COLUMN "is_primary" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION better_supabase.list_bank_accounts (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_bank_accounts.tenant is not null and coalesce(better_supabase.can('tenant', list_bank_accounts.tenant, 'banking.read'), false))) then
    raise exception 'not allowed to read bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'holder', x."holder", 'primary', x."is_primary", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id")
    from "better_supabase"."bank_accounts" x
    where x."tenant_id" = list_bank_accounts.tenant
      and (list_bank_accounts.include_archived or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_bank_account (
  tenant     uuid,
  input      jsonb,
  account_id uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_iban text;
  v_bic text;
  v_currency text;
  v_journal uuid;
  v_holder text;
  v_primary boolean;
  v_archived boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_bank_account.tenant is not null and coalesce(better_supabase.can('tenant', save_bank_account.tenant, 'banking.manage'), false))) then
    raise exception 'not allowed to manage bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_bank_account.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if save_bank_account.account_id is not null then
    select * into v_account from "better_supabase"."bank_accounts" x
    where x."id" = save_bank_account.account_id and x."tenant_id" = save_bank_account.tenant
    for update;
    if not found then
      raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
    end if;
  end if;
  v_iban := case when save_bank_account.input ? 'iban'
    then nullif(upper(regexp_replace(save_bank_account.input ->> 'iban', '\s', '', 'g')), '')
    else v_account."iban" end;
  if v_iban is not null and (v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'
    or "better_supabase"."bank_mod97"(substr(v_iban, 5) || substr(v_iban, 1, 4)) is distinct from 1) then
    raise exception 'the IBAN''s check digits don''t match' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  v_bic := case when save_bank_account.input ? 'bic'
    then nullif(upper(regexp_replace(save_bank_account.input ->> 'bic', '\s', '', 'g')), '')
    else v_account."bic" end;
  if v_bic is not null and v_bic !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then
    raise exception 'a BIC has 8 or 11 letters and digits' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  v_currency := upper(coalesce(save_bank_account.input ->> 'currency', v_account."currency"));
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'a bank account has an ISO 4217 currency' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if v_account."id" is not null and v_currency <> v_account."currency" and exists (
    select 1 from "better_supabase"."bank_transactions" y where y."account_id" = v_account."id"
  ) then
    raise exception 'a bank account with transactions keeps its currency' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  v_holder := case when save_bank_account.input ? 'holder'
    then nullif(trim(save_bank_account.input ->> 'holder'), '')
    else v_account."holder" end;
  v_archived := case when save_bank_account.input ? 'archived'
    then coalesce((save_bank_account.input ->> 'archived')::boolean, false)
    else v_account."archived_at" is not null end;
  v_primary := case when v_archived then false
    when save_bank_account.input ? 'primary' then coalesce((save_bank_account.input ->> 'primary')::boolean, false)
    else coalesce(v_account."is_primary", false) end;
  if v_primary then
    update "better_supabase"."bank_accounts" x set "is_primary" = false, "updated_at" = now()
    where x."tenant_id" = save_bank_account.tenant and x."currency" = v_currency
      and x."is_primary" and x."id" is distinct from v_account."id";
  end if;
  v_journal := case when save_bank_account.input ? 'journalId'
    then nullif(save_bank_account.input ->> 'journalId', '')::uuid
    else v_account."journal_id" end;
  if v_journal is not null and not exists (
    select 1 from "better_supabase"."accounting_journals" y
    where y."id" = v_journal and y."tenant_id" = save_bank_account.tenant
      and y."type" in ('bank', 'cash')
  ) then
    raise exception 'the journal must be a bank or cash journal of the organization' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if v_account."id" is null then
    insert into "better_supabase"."bank_accounts" ("tenant_id", "name", "holder", "is_primary", "iban", "bic", "currency", "journal_id")
    values (save_bank_account.tenant, trim(save_bank_account.input ->> 'name'), v_holder, v_primary, v_iban, v_bic, v_currency, v_journal)
    returning * into v_account;
  else
    update "better_supabase"."bank_accounts" x set
      "name" = coalesce(trim(save_bank_account.input ->> 'name'), x."name"),
      "holder" = v_holder,
      "is_primary" = v_primary,
      "iban" = v_iban,
      "bic" = v_bic,
      "currency" = v_currency,
      "journal_id" = v_journal,
      "archived_at" = case when save_bank_account.input ? 'archived'
        then case when (save_bank_account.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_account."id"
    returning * into v_account;
  end if;
  return jsonb_build_object('id', v_account."id", 'organizationId', v_account."tenant_id", 'name', v_account."name", 'iban', v_account."iban", 'bic', v_account."bic", 'currency', v_account."currency", 'holder', v_account."holder", 'primary', v_account."is_primary", 'journalId', v_account."journal_id", 'archivedAt', v_account."archived_at", 'createdAt', v_account."created_at", 'updatedAt', v_account."updated_at");
exception
  when check_violation or not_null_violation then
    raise exception 'a bank account has a name of 1 to 200 characters' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  when unique_violation then
    raise exception 'the organization already has a bank account with this IBAN' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  when invalid_text_representation then
    raise exception 'journalId must be a uuid' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
end;
$function$;

ALTER TABLE "better_supabase"."bank_accounts"
  ADD CONSTRAINT "bsb_bank_accounts_holder_check" CHECK (((holder IS NULL) OR ((length(holder) >= 1) AND (length(holder) <= 200))));

CREATE UNIQUE INDEX bank_accounts_primary_key ON better_supabase.bank_accounts USING btree (tenant_id, currency)
  WHERE (is_primary AND (archived_at IS NULL));
