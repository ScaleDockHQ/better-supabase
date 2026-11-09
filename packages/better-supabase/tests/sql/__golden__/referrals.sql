-- ==== alone: schema supabase/schemas/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block referrals@1 managed
-- @bsb-hash sha256:949b538a52bc22de2d53d8602adbab3daa9bab47ad8bc39a6bb82370c406f034
-- Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Referral codes and the referrals they bring. A code belongs to the member who
-- shares it, optionally to one invitation. Rewards are bigint minor units of a
-- ledger unit, posted once per referral.
create table "better_supabase"."referral_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null constraint bsb_referral_codes_code_check check ("code" ~ '^[A-Z0-9]{4,32}$'),
  "referrer_id" uuid not null,
  -- The invitation the code was made for, so accepting it attributes the referral.
  "invitation_id" uuid,
  "reward_amount" bigint not null default 0 constraint bsb_referral_codes_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text constraint bsb_referral_codes_reward_unit_check check ("reward_unit" is null or length("reward_unit") >= 1 and length("reward_unit") <= 32),
  "max_uses" integer constraint bsb_referral_codes_max_uses_check check ("max_uses" is null or "max_uses" > 0),
  "uses" integer not null default 0,
  "active" boolean not null default true,
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  unique ("tenant_id", "id"),
  constraint bsb_referral_codes_check check ("reward_amount" = 0 or "reward_unit" is not null)
);
create index referral_codes_referrer_idx on "better_supabase"."referral_codes" ("tenant_id", "referrer_id");
create unique index referral_codes_invitation_key on "better_supabase"."referral_codes" ("tenant_id", "invitation_id") where "invitation_id" is not null;
alter table "better_supabase"."referral_codes" enable row level security;
revoke all on "better_supabase"."referral_codes" from public, anon, authenticated;
grant select on "better_supabase"."referral_codes" to authenticated;
grant all on "better_supabase"."referral_codes" to service_role;
create policy bsb_referral_codes_read on "better_supabase"."referral_codes"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

create table "better_supabase"."referrals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code_id" uuid not null,
  "referrer_id" uuid not null,
  "referred_id" uuid,
  "referred_organization_id" uuid,
  "referred_email" text constraint bsb_referrals_referred_email_check check ("referred_email" is null or length("referred_email") <= 320),
  "status" text not null default 'attributed' constraint bsb_referrals_status_check check ("status" in ('attributed', 'qualified', 'rewarded', 'void')),
  -- The reward as the code promised it when the referral was attributed.
  "reward_amount" bigint not null default 0 constraint bsb_referrals_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text,
  "qualified_at" timestamptz,
  "qualified_by" text,
  "rewarded_at" timestamptz,
  "ledger_transaction_id" uuid,
  "voided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_referrals_check check ("referred_id" is not null or "referred_organization_id" is not null or "referred_email" is not null),
  foreign key ("tenant_id", "code_id") references "better_supabase"."referral_codes" ("tenant_id", "id") on delete cascade
);
create unique index referrals_user_key on "better_supabase"."referrals" ("tenant_id", "referred_id") where "referred_id" is not null;
create unique index referrals_organization_key on "better_supabase"."referrals" ("tenant_id", "referred_organization_id") where "referred_organization_id" is not null;
create index referrals_code_idx on "better_supabase"."referrals" ("tenant_id", "code_id");
create index referrals_referrer_idx on "better_supabase"."referrals" ("tenant_id", "referrer_id", "created_at" desc);
alter table "better_supabase"."referrals" enable row level security;
revoke all on "better_supabase"."referrals" from public, anon, authenticated;
grant select on "better_supabase"."referrals" to authenticated;
grant all on "better_supabase"."referrals" to service_role;
create policy bsb_referrals_read on "better_supabase"."referrals"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

-- Creates a referral code for a member (the caller by default). Making a code
-- for someone else needs referrals.manage, the own code referrals.write. code
-- is generated when omitted. The reward is paid in reward_unit on the ledger
-- when a referral qualifies. invitation_id ties the code to an invitation, so
-- accepting it attributes the referral.
create or replace function "better_supabase"."create_referral_code"(tenant uuid, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."referral_codes";
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_referrer is null then
    raise exception 'sign in to create a referral code' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.write'), false)))
    or (v_referrer is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false)))) then
    raise exception 'not allowed to create referral codes' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    raise exception 'a code is 4 to 32 letters or digits, and a reward needs a unit' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false))) then
    raise exception 'rewards, limits and expiry on a code need referrals.manage' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  insert into "better_supabase"."referral_codes" ("tenant_id", "code", "referrer_id", "invitation_id", "reward_amount", "reward_unit", "max_uses", "expires_at")
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id", 'rewardAmount', v_row."reward_amount"::text, 'rewardUnit', v_row."reward_unit", 'maxUses', v_row."max_uses", 'uses', v_row."uses", 'active', v_row."active", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) to authenticated, service_role;

-- Attributes a referral without checking the caller: attribute_referral and
-- the invitation trigger call it. Attributing a user or an organization that
-- already has a referral returns that referral.
create or replace function "better_supabase"."referral_attribute"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_code "better_supabase"."referral_codes";
  v_ref "better_supabase"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "better_supabase"."referral_codes" x
  where x."tenant_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "better_supabase"."referrals" ("tenant_id", "code_id", "referrer_id", "referred_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "better_supabase"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) to service_role;

-- Attributes the user or organization that signed up with a code. Calling it
-- again for the same user or organization returns the first referral. Needs
-- referrals.write.
create or replace function "better_supabase"."attribute_referral"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (attribute_referral.tenant is not null and coalesce(better_supabase.can('tenant', attribute_referral.tenant, 'referrals.write'), false))) then
    raise exception 'not allowed to attribute referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  return "better_supabase"."referral_attribute"(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$$;
revoke execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) to authenticated, service_role;

-- Marks the referral of a user or organization as qualified after the event
-- that earns the reward, such as its first paid invoice, and posts the reward
-- to the ledger when the code carries one: the reward expense account is
-- debited and the referrer's payable rewards account credited, once per
-- referral. source names what qualified it. Qualifying again returns the
-- referral. Needs referrals.manage.
create or replace function "better_supabase"."qualify_referral"(tenant uuid, referred_user uuid default null, referred_org uuid default null, source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "better_supabase"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "better_supabase"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    null;
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) to authenticated, service_role;

-- Voids a referral, for example after fraud or a refund. A reward already
-- posted is reversed on the ledger. Voiding a void referral returns it. Needs
-- referrals.manage.
create or replace function "better_supabase"."void_referral"(referral_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "better_supabase"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "better_supabase"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."void_referral"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_referral"(uuid, text) to authenticated, service_role;

-- An organization's referrals, newest first. filters is { referrer, status,
-- limit }. Needs referrals.read; without it a member sees the referrals of
-- their own codes.
create or replace function "better_supabase"."list_referrals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referrals" z
      where z."tenant_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referrals"(uuid, jsonb) to authenticated, service_role;

-- An organization's referral codes, newest first. filters is { referrer,
-- limit }. Needs referrals.read; without it a member sees their own codes.
create or replace function "better_supabase"."list_referral_codes"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'referrerId', y."referrer_id", 'invitationId', y."invitation_id", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'maxUses', y."max_uses", 'uses', y."uses", 'active', y."active", 'expiresAt', y."expires_at", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referral_codes" z
      where z."tenant_id" = list_referral_codes.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."referral_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referral_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referral_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referral_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."referrals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referrals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referrals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referrals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block-data referrals
-- @bsb-hash sha256:ceb9afb90afb8e28f7810b7fb091d8845f340739a53570a530fd9a63c84d22f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block referrals@1 managed
-- @bsb-hash sha256:e5cecb61ffd9628c9ec4538d4b159340df10bee2d61b596550ded37055a97d96
-- Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Referral codes and the referrals they bring. A code belongs to the member who
-- shares it, optionally to one invitation. Rewards are bigint minor units of a
-- ledger unit, posted once per referral.
create table "better_supabase"."referral_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null constraint bsb_referral_codes_code_check check ("code" ~ '^[A-Z0-9]{4,32}$'),
  "referrer_id" uuid not null,
  -- The invitation the code was made for, so accepting it attributes the referral.
  "invitation_id" uuid,
  "reward_amount" bigint not null default 0 constraint bsb_referral_codes_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text constraint bsb_referral_codes_reward_unit_check check ("reward_unit" is null or length("reward_unit") >= 1 and length("reward_unit") <= 32),
  "max_uses" integer constraint bsb_referral_codes_max_uses_check check ("max_uses" is null or "max_uses" > 0),
  "uses" integer not null default 0,
  "active" boolean not null default true,
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  unique ("tenant_id", "id"),
  constraint bsb_referral_codes_check check ("reward_amount" = 0 or "reward_unit" is not null)
);
create index referral_codes_referrer_idx on "better_supabase"."referral_codes" ("tenant_id", "referrer_id");
create unique index referral_codes_invitation_key on "better_supabase"."referral_codes" ("tenant_id", "invitation_id") where "invitation_id" is not null;
alter table "better_supabase"."referral_codes" enable row level security;
revoke all on "better_supabase"."referral_codes" from public, anon, authenticated;
grant select on "better_supabase"."referral_codes" to authenticated;
grant all on "better_supabase"."referral_codes" to service_role;
create policy bsb_referral_codes_read on "better_supabase"."referral_codes"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

create table "better_supabase"."referrals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code_id" uuid not null,
  "referrer_id" uuid not null,
  "referred_id" uuid,
  "referred_organization_id" uuid,
  "referred_email" text constraint bsb_referrals_referred_email_check check ("referred_email" is null or length("referred_email") <= 320),
  "status" text not null default 'attributed' constraint bsb_referrals_status_check check ("status" in ('attributed', 'qualified', 'rewarded', 'void')),
  -- The reward as the code promised it when the referral was attributed.
  "reward_amount" bigint not null default 0 constraint bsb_referrals_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text,
  "qualified_at" timestamptz,
  "qualified_by" text,
  "rewarded_at" timestamptz,
  "ledger_transaction_id" uuid,
  "voided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_referrals_check check ("referred_id" is not null or "referred_organization_id" is not null or "referred_email" is not null),
  foreign key ("tenant_id", "code_id") references "better_supabase"."referral_codes" ("tenant_id", "id") on delete cascade
);
create unique index referrals_user_key on "better_supabase"."referrals" ("tenant_id", "referred_id") where "referred_id" is not null;
create unique index referrals_organization_key on "better_supabase"."referrals" ("tenant_id", "referred_organization_id") where "referred_organization_id" is not null;
create index referrals_code_idx on "better_supabase"."referrals" ("tenant_id", "code_id");
create index referrals_referrer_idx on "better_supabase"."referrals" ("tenant_id", "referrer_id", "created_at" desc);
alter table "better_supabase"."referrals" enable row level security;
revoke all on "better_supabase"."referrals" from public, anon, authenticated;
grant select on "better_supabase"."referrals" to authenticated;
grant all on "better_supabase"."referrals" to service_role;
create policy bsb_referrals_read on "better_supabase"."referrals"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

-- Creates a referral code for a member (the caller by default). Making a code
-- for someone else needs referrals.manage, the own code referrals.write. code
-- is generated when omitted. The reward is paid in reward_unit on the ledger
-- when a referral qualifies. invitation_id ties the code to an invitation, so
-- accepting it attributes the referral.
create or replace function "better_supabase"."create_referral_code"(tenant uuid, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."referral_codes";
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_referrer is null then
    raise exception 'sign in to create a referral code' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.write'), false)))
    or (v_referrer is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false)))) then
    raise exception 'not allowed to create referral codes' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    raise exception 'a code is 4 to 32 letters or digits, and a reward needs a unit' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false))) then
    raise exception 'rewards, limits and expiry on a code need referrals.manage' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  insert into "better_supabase"."referral_codes" ("tenant_id", "code", "referrer_id", "invitation_id", "reward_amount", "reward_unit", "max_uses", "expires_at")
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  perform "better_supabase".emit_event('referral_code.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id"), 'referral-codes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral_code.created',
    category => 'data',
    target_type => 'referral_code',
    record_id => v_row."id"::text,
    target_label => v_row."code",
    summary => 'created a referral code',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id", 'rewardAmount', v_row."reward_amount"::text, 'rewardUnit', v_row."reward_unit", 'maxUses', v_row."max_uses", 'uses', v_row."uses", 'active', v_row."active", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) to authenticated, service_role;

-- Attributes a referral without checking the caller: attribute_referral and
-- the invitation trigger call it. Attributing a user or an organization that
-- already has a referral returns that referral.
create or replace function "better_supabase"."referral_attribute"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_code "better_supabase"."referral_codes";
  v_ref "better_supabase"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "better_supabase"."referral_codes" x
  where x."tenant_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "better_supabase"."referrals" ("tenant_id", "code_id", "referrer_id", "referred_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "better_supabase"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  perform "better_supabase".emit_event('referral.attributed', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.attributed',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral attributed',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) to service_role;

-- Attributes the user or organization that signed up with a code. Calling it
-- again for the same user or organization returns the first referral. Needs
-- referrals.write.
create or replace function "better_supabase"."attribute_referral"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (attribute_referral.tenant is not null and coalesce(better_supabase.can('tenant', attribute_referral.tenant, 'referrals.write'), false))) then
    raise exception 'not allowed to attribute referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  return "better_supabase"."referral_attribute"(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$$;
revoke execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) to authenticated, service_role;

-- Marks the referral of a user or organization as qualified after the event
-- that earns the reward, such as its first paid invoice, and posts the reward
-- to the ledger when the code carries one: the reward expense account is
-- debited and the referrer's payable rewards account credited, once per
-- referral. source names what qualified it. Qualifying again returns the
-- referral. Needs referrals.manage.
create or replace function "better_supabase"."qualify_referral"(tenant uuid, referred_user uuid default null, referred_org uuid default null, source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "better_supabase"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  perform "better_supabase".emit_event('referral.qualified', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.qualified',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral qualified',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "better_supabase"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    perform "better_supabase".emit_event('referral.rewarded', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status", 'amount', v_ref."reward_amount"::text, 'unit', v_ref."reward_unit"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.rewarded',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral rewarded',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status", 'amount', v_ref."reward_amount"::text, 'unit', v_ref."reward_unit")
  );
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) to authenticated, service_role;

-- Voids a referral, for example after fraud or a refund. A reward already
-- posted is reversed on the ledger. Voiding a void referral returns it. Needs
-- referrals.manage.
create or replace function "better_supabase"."void_referral"(referral_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "better_supabase"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "better_supabase"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  perform "better_supabase".emit_event('referral.voided', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.voided',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral voided',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."void_referral"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_referral"(uuid, text) to authenticated, service_role;

-- An organization's referrals, newest first. filters is { referrer, status,
-- limit }. Needs referrals.read; without it a member sees the referrals of
-- their own codes.
create or replace function "better_supabase"."list_referrals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referrals" z
      where z."tenant_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referrals"(uuid, jsonb) to authenticated, service_role;

-- An organization's referral codes, newest first. filters is { referrer,
-- limit }. Needs referrals.read; without it a member sees their own codes.
create or replace function "better_supabase"."list_referral_codes"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'referrerId', y."referrer_id", 'invitationId', y."invitation_id", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'maxUses', y."max_uses", 'uses', y."uses", 'active', y."active", 'expiresAt', y."expires_at", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referral_codes" z
      where z."tenant_id" = list_referral_codes.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."referral_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referral_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referral_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referral_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."referrals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referrals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referrals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referrals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.referral_codes deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"referral_code","event_prefix":"referral_code"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.referrals deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"referral","event_prefix":"referral"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block-data referrals
-- @bsb-hash sha256:ceb9afb90afb8e28f7810b7fb091d8845f340739a53570a530fd9a63c84d22f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block referrals@1 managed
-- @bsb-hash sha256:d6b4d2060f7e06471e7ad382b745f8b9ef36a182638863a4f6d023fc1462f2bb
-- Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Referral codes and the referrals they bring. A code belongs to the member who
-- shares it, optionally to one invitation. Rewards are bigint minor units of a
-- ledger unit, posted once per referral.
create table "app_private"."referral_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null constraint bsb_referral_codes_code_check check ("code" ~ '^[A-Z0-9]{4,32}$'),
  "referrer_id" uuid not null,
  -- The invitation the code was made for, so accepting it attributes the referral.
  "invitation_id" uuid,
  "reward_amount" bigint not null default 0 constraint bsb_referral_codes_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text constraint bsb_referral_codes_reward_unit_check check ("reward_unit" is null or length("reward_unit") >= 1 and length("reward_unit") <= 32),
  "max_uses" integer constraint bsb_referral_codes_max_uses_check check ("max_uses" is null or "max_uses" > 0),
  "uses" integer not null default 0,
  "active" boolean not null default true,
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  unique ("tenant_id", "id"),
  constraint bsb_referral_codes_check check ("reward_amount" = 0 or "reward_unit" is not null)
);
create index referral_codes_referrer_idx on "app_private"."referral_codes" ("tenant_id", "referrer_id");
create unique index referral_codes_invitation_key on "app_private"."referral_codes" ("tenant_id", "invitation_id") where "invitation_id" is not null;
alter table "app_private"."referral_codes" enable row level security;
revoke all on "app_private"."referral_codes" from public, anon, authenticated;
grant select on "app_private"."referral_codes" to authenticated;
grant all on "app_private"."referral_codes" to service_role;
create policy bsb_referral_codes_read on "app_private"."referral_codes"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

create table "app_private"."referrals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code_id" uuid not null,
  "referrer_id" uuid not null,
  "referred_id" uuid,
  "referred_organization_id" uuid,
  "referred_email" text constraint bsb_referrals_referred_email_check check ("referred_email" is null or length("referred_email") <= 320),
  "status" text not null default 'attributed' constraint bsb_referrals_status_check check ("status" in ('attributed', 'qualified', 'rewarded', 'void')),
  -- The reward as the code promised it when the referral was attributed.
  "reward_amount" bigint not null default 0 constraint bsb_referrals_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text,
  "qualified_at" timestamptz,
  "qualified_by" text,
  "rewarded_at" timestamptz,
  "ledger_transaction_id" uuid,
  "voided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_referrals_check check ("referred_id" is not null or "referred_organization_id" is not null or "referred_email" is not null),
  foreign key ("tenant_id", "code_id") references "app_private"."referral_codes" ("tenant_id", "id") on delete cascade
);
create unique index referrals_user_key on "app_private"."referrals" ("tenant_id", "referred_id") where "referred_id" is not null;
create unique index referrals_organization_key on "app_private"."referrals" ("tenant_id", "referred_organization_id") where "referred_organization_id" is not null;
create index referrals_code_idx on "app_private"."referrals" ("tenant_id", "code_id");
create index referrals_referrer_idx on "app_private"."referrals" ("tenant_id", "referrer_id", "created_at" desc);
alter table "app_private"."referrals" enable row level security;
revoke all on "app_private"."referrals" from public, anon, authenticated;
grant select on "app_private"."referrals" to authenticated;
grant all on "app_private"."referrals" to service_role;
create policy bsb_referrals_read on "app_private"."referrals"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

-- Creates a referral code for a member (the caller by default). Making a code
-- for someone else needs referrals.manage, the own code referrals.write. code
-- is generated when omitted. The reward is paid in reward_unit on the ledger
-- when a referral qualifies. invitation_id ties the code to an invitation, so
-- accepting it attributes the referral.
create or replace function "app_private"."create_referral_code"(tenant uuid, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."referral_codes";
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_referrer is null then
    raise exception 'sign in to create a referral code' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.write'), false)))
    or (v_referrer is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false)))) then
    raise exception 'not allowed to create referral codes' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    raise exception 'a code is 4 to 32 letters or digits, and a reward needs a unit' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false))) then
    raise exception 'rewards, limits and expiry on a code need referrals.manage' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  insert into "app_private"."referral_codes" ("tenant_id", "code", "referrer_id", "invitation_id", "reward_amount", "reward_unit", "max_uses", "expires_at")
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id", 'rewardAmount', v_row."reward_amount"::text, 'rewardUnit', v_row."reward_unit", 'maxUses', v_row."max_uses", 'uses', v_row."uses", 'active', v_row."active", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) from public, anon;
grant execute on function "app_private"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) to authenticated, service_role;

-- Attributes a referral without checking the caller: attribute_referral and
-- the invitation trigger call it. Attributing a user or an organization that
-- already has a referral returns that referral.
create or replace function "app_private"."referral_attribute"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_code "app_private"."referral_codes";
  v_ref "app_private"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "app_private"."referrals" x
  where x."tenant_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "app_private"."referral_codes" x
  where x."tenant_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "app_private"."referrals" ("tenant_id", "code_id", "referrer_id", "referred_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "app_private"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "app_private"."referral_attribute"(uuid, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function "app_private"."referral_attribute"(uuid, text, uuid, uuid, text) to service_role;

-- Attributes the user or organization that signed up with a code. Calling it
-- again for the same user or organization returns the first referral. Needs
-- referrals.write.
create or replace function "app_private"."attribute_referral"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (attribute_referral.tenant is not null and coalesce(better_supabase.can('tenant', attribute_referral.tenant, 'referrals.write'), false))) then
    raise exception 'not allowed to attribute referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  return "app_private"."referral_attribute"(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$$;
revoke execute on function "app_private"."attribute_referral"(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function "app_private"."attribute_referral"(uuid, text, uuid, uuid, text) to authenticated, service_role;

-- Marks the referral of a user or organization as qualified after the event
-- that earns the reward, such as its first paid invoice, and posts the reward
-- to the ledger when the code carries one: the reward expense account is
-- debited and the referrer's payable rewards account credited, once per
-- referral. source names what qualified it. Qualifying again returns the
-- referral. Needs referrals.manage.
create or replace function "app_private"."qualify_referral"(tenant uuid, referred_user uuid default null, referred_org uuid default null, source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "app_private"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "app_private"."referrals" x
  where x."tenant_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "app_private"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "app_private"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    null;
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "app_private"."qualify_referral"(uuid, uuid, uuid, text) from public, anon;
grant execute on function "app_private"."qualify_referral"(uuid, uuid, uuid, text) to authenticated, service_role;

-- Voids a referral, for example after fraud or a refund. A reward already
-- posted is reversed on the ledger. Voiding a void referral returns it. Needs
-- referrals.manage.
create or replace function "app_private"."void_referral"(referral_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "app_private"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "app_private"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "app_private"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "app_private"."void_referral"(uuid, text) from public, anon;
grant execute on function "app_private"."void_referral"(uuid, text) to authenticated, service_role;

-- An organization's referrals, newest first. filters is { referrer, status,
-- limit }. Needs referrals.read; without it a member sees the referrals of
-- their own codes.
create or replace function "app_private"."list_referrals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "app_private"."referrals" z
      where z."tenant_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_referrals"(uuid, jsonb) to authenticated, service_role;

-- An organization's referral codes, newest first. filters is { referrer,
-- limit }. Needs referrals.read; without it a member sees their own codes.
create or replace function "app_private"."list_referral_codes"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'referrerId', y."referrer_id", 'invitationId', y."invitation_id", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'maxUses', y."max_uses", 'uses', y."uses", 'active', y."active", 'expiresAt', y."expires_at", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "app_private"."referral_codes" z
      where z."tenant_id" = list_referral_codes.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_referral_codes"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_referral_codes"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."referral_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "app_private"."referral_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."referral_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."referral_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."referrals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "app_private"."referrals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."referrals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."referrals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block-data referrals
-- @bsb-hash sha256:ceb9afb90afb8e28f7810b7fb091d8845f340739a53570a530fd9a63c84d22f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block referrals@1 managed
-- @bsb-hash sha256:48e77054e640979e73f15e252c039f6419eee59ee9499939626536da0dbf2019
-- Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Referral codes and the referrals they bring. A code belongs to the member who
-- shares it, optionally to one invitation. Rewards are bigint minor units of a
-- ledger unit, posted once per referral.
create table "better_supabase"."referral_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null constraint bsb_referral_codes_code_check check ("code" ~ '^[A-Z0-9]{4,32}$'),
  "referrer_id" uuid not null,
  -- The invitation the code was made for, so accepting it attributes the referral.
  "invitation_id" uuid,
  "reward_amount" bigint not null default 0 constraint bsb_referral_codes_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text constraint bsb_referral_codes_reward_unit_check check ("reward_unit" is null or length("reward_unit") >= 1 and length("reward_unit") <= 32),
  "max_uses" integer constraint bsb_referral_codes_max_uses_check check ("max_uses" is null or "max_uses" > 0),
  "uses" integer not null default 0,
  "active" boolean not null default true,
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  unique ("tenant_id", "id"),
  constraint bsb_referral_codes_check check ("reward_amount" = 0 or "reward_unit" is not null)
);
create index referral_codes_referrer_idx on "better_supabase"."referral_codes" ("tenant_id", "referrer_id");
create unique index referral_codes_invitation_key on "better_supabase"."referral_codes" ("tenant_id", "invitation_id") where "invitation_id" is not null;
alter table "better_supabase"."referral_codes" enable row level security;
revoke all on "better_supabase"."referral_codes" from public, anon, authenticated;
grant select on "better_supabase"."referral_codes" to authenticated;
grant all on "better_supabase"."referral_codes" to service_role;
create policy bsb_referral_codes_read on "better_supabase"."referral_codes"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

create table "better_supabase"."referrals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code_id" uuid not null,
  "referrer_id" uuid not null,
  "referred_id" uuid,
  "referred_organization_id" uuid,
  "referred_email" text constraint bsb_referrals_referred_email_check check ("referred_email" is null or length("referred_email") <= 320),
  "status" text not null default 'attributed' constraint bsb_referrals_status_check check ("status" in ('attributed', 'qualified', 'rewarded', 'void')),
  -- The reward as the code promised it when the referral was attributed.
  "reward_amount" bigint not null default 0 constraint bsb_referrals_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text,
  "qualified_at" timestamptz,
  "qualified_by" text,
  "rewarded_at" timestamptz,
  "ledger_transaction_id" uuid,
  "voided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_referrals_check check ("referred_id" is not null or "referred_organization_id" is not null or "referred_email" is not null),
  foreign key ("tenant_id", "code_id") references "better_supabase"."referral_codes" ("tenant_id", "id") on delete cascade
);
create unique index referrals_user_key on "better_supabase"."referrals" ("tenant_id", "referred_id") where "referred_id" is not null;
create unique index referrals_organization_key on "better_supabase"."referrals" ("tenant_id", "referred_organization_id") where "referred_organization_id" is not null;
create index referrals_code_idx on "better_supabase"."referrals" ("tenant_id", "code_id");
create index referrals_referrer_idx on "better_supabase"."referrals" ("tenant_id", "referrer_id", "created_at" desc);
alter table "better_supabase"."referrals" enable row level security;
revoke all on "better_supabase"."referrals" from public, anon, authenticated;
grant select on "better_supabase"."referrals" to authenticated;
grant all on "better_supabase"."referrals" to service_role;
create policy bsb_referrals_read on "better_supabase"."referrals"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

-- Creates a referral code for a member (the caller by default). Making a code
-- for someone else needs referrals.manage, the own code referrals.write. code
-- is generated when omitted. The reward is paid in reward_unit on the ledger
-- when a referral qualifies. invitation_id ties the code to an invitation, so
-- accepting it attributes the referral.
create or replace function "better_supabase"."create_referral_code"(tenant uuid, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."referral_codes";
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_referrer is null then
    raise exception 'sign in to create a referral code' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.write'), false)))
    or (v_referrer is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false)))) then
    raise exception 'not allowed to create referral codes' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    raise exception 'a code is 4 to 32 letters or digits, and a reward needs a unit' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false))) then
    raise exception 'rewards, limits and expiry on a code need referrals.manage' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  insert into "better_supabase"."referral_codes" ("tenant_id", "code", "referrer_id", "invitation_id", "reward_amount", "reward_unit", "max_uses", "expires_at")
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id", 'rewardAmount', v_row."reward_amount"::text, 'rewardUnit', v_row."reward_unit", 'maxUses', v_row."max_uses", 'uses', v_row."uses", 'active', v_row."active", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) to authenticated, service_role;

-- Attributes a referral without checking the caller: attribute_referral and
-- the invitation trigger call it. Attributing a user or an organization that
-- already has a referral returns that referral.
create or replace function "better_supabase"."referral_attribute"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_code "better_supabase"."referral_codes";
  v_ref "better_supabase"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "better_supabase"."referral_codes" x
  where x."tenant_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "better_supabase"."referrals" ("tenant_id", "code_id", "referrer_id", "referred_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "better_supabase"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) to service_role;

-- Attributes the user or organization that signed up with a code. Calling it
-- again for the same user or organization returns the first referral. Needs
-- referrals.write.
create or replace function "better_supabase"."attribute_referral"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (attribute_referral.tenant is not null and coalesce(better_supabase.can('tenant', attribute_referral.tenant, 'referrals.write'), false))) then
    raise exception 'not allowed to attribute referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  return "better_supabase"."referral_attribute"(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$$;
revoke execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) to authenticated, service_role;

-- Marks the referral of a user or organization as qualified after the event
-- that earns the reward, such as its first paid invoice, and posts the reward
-- to the ledger when the code carries one: the reward expense account is
-- debited and the referrer's payable rewards account credited, once per
-- referral. source names what qualified it. Qualifying again returns the
-- referral. Needs referrals.manage.
create or replace function "better_supabase"."qualify_referral"(tenant uuid, referred_user uuid default null, referred_org uuid default null, source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "better_supabase"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "better_supabase"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    null;
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) to authenticated, service_role;

-- Voids a referral, for example after fraud or a refund. A reward already
-- posted is reversed on the ledger. Voiding a void referral returns it. Needs
-- referrals.manage.
create or replace function "better_supabase"."void_referral"(referral_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "better_supabase"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "better_supabase"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."void_referral"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_referral"(uuid, text) to authenticated, service_role;

-- An organization's referrals, newest first. filters is { referrer, status,
-- limit }. Needs referrals.read; without it a member sees the referrals of
-- their own codes.
create or replace function "better_supabase"."list_referrals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referrals" z
      where z."tenant_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referrals"(uuid, jsonb) to authenticated, service_role;

-- An organization's referral codes, newest first. filters is { referrer,
-- limit }. Needs referrals.read; without it a member sees their own codes.
create or replace function "better_supabase"."list_referral_codes"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'referrerId', y."referrer_id", 'invitationId', y."invitation_id", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'maxUses', y."max_uses", 'uses', y."uses", 'active', y."active", 'expiresAt', y."expires_at", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referral_codes" z
      where z."tenant_id" = list_referral_codes.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."referral_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referral_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referral_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referral_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."referrals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referrals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referrals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referrals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.referrals.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_referral_code"(tenant uuid, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_referral_code"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) from public, anon;
grant execute on function "api"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."referral_attribute"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."referral_attribute"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."referral_attribute"(uuid, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function "api"."referral_attribute"(uuid, text, uuid, uuid, text) to service_role;

create or replace function "api"."attribute_referral"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."attribute_referral"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."attribute_referral"(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function "api"."attribute_referral"(uuid, text, uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."qualify_referral"(tenant uuid, referred_user uuid default null, referred_org uuid default null, source text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."qualify_referral"($1, $2, $3, $4) $$;
revoke execute on function "api"."qualify_referral"(uuid, uuid, uuid, text) from public, anon;
grant execute on function "api"."qualify_referral"(uuid, uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."void_referral"(referral_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."void_referral"($1, $2) $$;
revoke execute on function "api"."void_referral"(uuid, text) from public, anon;
grant execute on function "api"."void_referral"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_referrals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_referrals"($1, $2) $$;
revoke execute on function "api"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_referrals"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_referral_codes"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_referral_codes"($1, $2) $$;
revoke execute on function "api"."list_referral_codes"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_referral_codes"(uuid, jsonb) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block-data referrals
-- @bsb-hash sha256:ceb9afb90afb8e28f7810b7fb091d8845f340739a53570a530fd9a63c84d22f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block referrals@1 managed
-- @bsb-hash sha256:483040a91b5c32b2ca61250cdd75666605e7d4d503b74111c1532f389165d3d0
-- Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Referral codes and the referrals they bring. A code belongs to the member who
-- shares it, optionally to one invitation. Rewards are bigint minor units of a
-- ledger unit, posted once per referral.
-- better_supabase.referral_codes is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."referral_codes" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."referral_codes" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."referral_codes" add column if not exists "code" text constraint bsb_referral_codes_code_check check ("code" ~ '^[A-Z0-9]{4,32}$');
alter table "better_supabase"."referral_codes" add column if not exists "referrer_id" uuid;
alter table "better_supabase"."referral_codes" add column if not exists "invitation_id" uuid;
alter table "better_supabase"."referral_codes" add column if not exists "reward_amount" bigint not null default 0 constraint bsb_referral_codes_reward_amount_check check ("reward_amount" >= 0);
alter table "better_supabase"."referral_codes" add column if not exists "reward_unit" text constraint bsb_referral_codes_reward_unit_check check ("reward_unit" is null or length("reward_unit") >= 1 and length("reward_unit") <= 32);
alter table "better_supabase"."referral_codes" add column if not exists "max_uses" integer constraint bsb_referral_codes_max_uses_check check ("max_uses" is null or "max_uses" > 0);
alter table "better_supabase"."referral_codes" add column if not exists "uses" integer not null default 0;
alter table "better_supabase"."referral_codes" add column if not exists "active" boolean not null default true;
alter table "better_supabase"."referral_codes" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."referral_codes" add column if not exists "created_at" timestamptz not null default now();
create index if not exists referral_codes_referrer_idx on "better_supabase"."referral_codes" ("tenant_id", "referrer_id");
create unique index if not exists referral_codes_invitation_key on "better_supabase"."referral_codes" ("tenant_id", "invitation_id") where "invitation_id" is not null;
alter table "better_supabase"."referral_codes" enable row level security;
grant select on "better_supabase"."referral_codes" to authenticated;
grant all on "better_supabase"."referral_codes" to service_role;
create policy bsb_referral_codes_select on "better_supabase"."referral_codes"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

-- better_supabase.referrals is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."referrals" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."referrals" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."referrals" add column if not exists "code_id" uuid;
alter table "better_supabase"."referrals" add column if not exists "referrer_id" uuid;
alter table "better_supabase"."referrals" add column if not exists "referred_id" uuid;
alter table "better_supabase"."referrals" add column if not exists "referred_organization_id" uuid;
alter table "better_supabase"."referrals" add column if not exists "referred_email" text constraint bsb_referrals_referred_email_check check ("referred_email" is null or length("referred_email") <= 320);
alter table "better_supabase"."referrals" add column if not exists "status" text not null default 'attributed' constraint bsb_referrals_status_check check ("status" in ('attributed', 'qualified', 'rewarded', 'void'));
alter table "better_supabase"."referrals" add column if not exists "reward_amount" bigint not null default 0 constraint bsb_referrals_reward_amount_check check ("reward_amount" >= 0);
alter table "better_supabase"."referrals" add column if not exists "reward_unit" text;
alter table "better_supabase"."referrals" add column if not exists "qualified_at" timestamptz;
alter table "better_supabase"."referrals" add column if not exists "qualified_by" text;
alter table "better_supabase"."referrals" add column if not exists "rewarded_at" timestamptz;
alter table "better_supabase"."referrals" add column if not exists "ledger_transaction_id" uuid;
alter table "better_supabase"."referrals" add column if not exists "voided_at" timestamptz;
alter table "better_supabase"."referrals" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists referrals_user_key on "better_supabase"."referrals" ("tenant_id", "referred_id") where "referred_id" is not null;
create unique index if not exists referrals_organization_key on "better_supabase"."referrals" ("tenant_id", "referred_organization_id") where "referred_organization_id" is not null;
create index if not exists referrals_code_idx on "better_supabase"."referrals" ("tenant_id", "code_id");
create index if not exists referrals_referrer_idx on "better_supabase"."referrals" ("tenant_id", "referrer_id", "created_at" desc);
alter table "better_supabase"."referrals" enable row level security;
grant select on "better_supabase"."referrals" to authenticated;
grant all on "better_supabase"."referrals" to service_role;
create policy bsb_referrals_select on "better_supabase"."referrals"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

-- Creates a referral code for a member (the caller by default). Making a code
-- for someone else needs referrals.manage, the own code referrals.write. code
-- is generated when omitted. The reward is paid in reward_unit on the ledger
-- when a referral qualifies. invitation_id ties the code to an invitation, so
-- accepting it attributes the referral.
create or replace function "better_supabase"."create_referral_code"(tenant uuid, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."referral_codes";
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_referrer is null then
    raise exception 'sign in to create a referral code' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.write'), false)))
    or (v_referrer is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false)))) then
    raise exception 'not allowed to create referral codes' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    raise exception 'a code is 4 to 32 letters or digits, and a reward needs a unit' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false))) then
    raise exception 'rewards, limits and expiry on a code need referrals.manage' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  insert into "better_supabase"."referral_codes" ("tenant_id", "code", "referrer_id", "invitation_id", "reward_amount", "reward_unit", "max_uses", "expires_at")
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id", 'rewardAmount', v_row."reward_amount"::text, 'rewardUnit', v_row."reward_unit", 'maxUses', v_row."max_uses", 'uses', v_row."uses", 'active', v_row."active", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) to authenticated, service_role;

-- Attributes a referral without checking the caller: attribute_referral and
-- the invitation trigger call it. Attributing a user or an organization that
-- already has a referral returns that referral.
create or replace function "better_supabase"."referral_attribute"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_code "better_supabase"."referral_codes";
  v_ref "better_supabase"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "better_supabase"."referral_codes" x
  where x."tenant_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "better_supabase"."referrals" ("tenant_id", "code_id", "referrer_id", "referred_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "better_supabase"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) to service_role;

-- Attributes the user or organization that signed up with a code. Calling it
-- again for the same user or organization returns the first referral. Needs
-- referrals.write.
create or replace function "better_supabase"."attribute_referral"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (attribute_referral.tenant is not null and coalesce(better_supabase.can('tenant', attribute_referral.tenant, 'referrals.write'), false))) then
    raise exception 'not allowed to attribute referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  return "better_supabase"."referral_attribute"(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$$;
revoke execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) to authenticated, service_role;

-- Marks the referral of a user or organization as qualified after the event
-- that earns the reward, such as its first paid invoice, and posts the reward
-- to the ledger when the code carries one: the reward expense account is
-- debited and the referrer's payable rewards account credited, once per
-- referral. source names what qualified it. Qualifying again returns the
-- referral. Needs referrals.manage.
create or replace function "better_supabase"."qualify_referral"(tenant uuid, referred_user uuid default null, referred_org uuid default null, source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "better_supabase"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "better_supabase"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    null;
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) to authenticated, service_role;

-- Voids a referral, for example after fraud or a refund. A reward already
-- posted is reversed on the ledger. Voiding a void referral returns it. Needs
-- referrals.manage.
create or replace function "better_supabase"."void_referral"(referral_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "better_supabase"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "better_supabase"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."void_referral"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_referral"(uuid, text) to authenticated, service_role;

-- An organization's referrals, newest first. filters is { referrer, status,
-- limit }. Needs referrals.read; without it a member sees the referrals of
-- their own codes.
create or replace function "better_supabase"."list_referrals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referrals" z
      where z."tenant_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referrals"(uuid, jsonb) to authenticated, service_role;

-- An organization's referral codes, newest first. filters is { referrer,
-- limit }. Needs referrals.read; without it a member sees their own codes.
create or replace function "better_supabase"."list_referral_codes"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'referrerId', y."referrer_id", 'invitationId', y."invitation_id", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'maxUses', y."max_uses", 'uses', y."uses", 'active', y."active", 'expiresAt', y."expires_at", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referral_codes" z
      where z."tenant_id" = list_referral_codes.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."referral_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referral_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referral_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referral_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."referrals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referrals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referrals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referrals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block-data referrals
-- @bsb-hash sha256:ceb9afb90afb8e28f7810b7fb091d8845f340739a53570a530fd9a63c84d22f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block referrals@1 managed
-- @bsb-hash sha256:fe496c13fd2191b4dc3a9262bce6fb3441d48bc027ad3f14064033e8982cf120
-- Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Referral codes and the referrals they bring. A code belongs to the member who
-- shares it, optionally to one invitation. Rewards are bigint minor units of a
-- ledger unit, posted once per referral.
create table "better_supabase"."referral_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "code" text not null constraint bsb_referral_codes_code_check check ("code" ~ '^[A-Z0-9]{4,32}$'),
  "referrer_id" uuid not null,
  -- The invitation the code was made for, so accepting it attributes the referral.
  "invitation_id" uuid,
  "reward_amount" bigint not null default 0 constraint bsb_referral_codes_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text constraint bsb_referral_codes_reward_unit_check check ("reward_unit" is null or length("reward_unit") >= 1 and length("reward_unit") <= 32),
  "max_uses" integer constraint bsb_referral_codes_max_uses_check check ("max_uses" is null or "max_uses" > 0),
  "uses" integer not null default 0,
  "active" boolean not null default true,
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("org_id", "code"),
  unique ("org_id", "id"),
  constraint bsb_referral_codes_check check ("reward_amount" = 0 or "reward_unit" is not null)
);
create index referral_codes_referrer_idx on "better_supabase"."referral_codes" ("org_id", "referrer_id");
create unique index referral_codes_invitation_key on "better_supabase"."referral_codes" ("org_id", "invitation_id") where "invitation_id" is not null;
alter table "better_supabase"."referral_codes" enable row level security;
revoke all on "better_supabase"."referral_codes" from public, anon, authenticated;
grant select on "better_supabase"."referral_codes" to authenticated;
grant all on "better_supabase"."referral_codes" to service_role;
create policy bsb_referral_codes_read on "better_supabase"."referral_codes"
  for select to authenticated
  using (("org_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

create table "better_supabase"."referrals" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "code_id" uuid not null,
  "referrer_id" uuid not null,
  "referred_id" uuid,
  "referred_organization_id" uuid,
  "referred_email" text constraint bsb_referrals_referred_email_check check ("referred_email" is null or length("referred_email") <= 320),
  "status" text not null default 'attributed' constraint bsb_referrals_status_check check ("status" in ('attributed', 'qualified', 'rewarded', 'void')),
  -- The reward as the code promised it when the referral was attributed.
  "reward_amount" bigint not null default 0 constraint bsb_referrals_reward_amount_check check ("reward_amount" >= 0),
  "reward_unit" text,
  "qualified_at" timestamptz,
  "qualified_by" text,
  "rewarded_at" timestamptz,
  "ledger_transaction_id" uuid,
  "voided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint bsb_referrals_check check ("referred_id" is not null or "referred_organization_id" is not null or "referred_email" is not null),
  foreign key ("org_id", "code_id") references "better_supabase"."referral_codes" ("org_id", "id") on delete cascade
);
create unique index referrals_user_key on "better_supabase"."referrals" ("org_id", "referred_id") where "referred_id" is not null;
create unique index referrals_organization_key on "better_supabase"."referrals" ("org_id", "referred_organization_id") where "referred_organization_id" is not null;
create index referrals_code_idx on "better_supabase"."referrals" ("org_id", "code_id");
create index referrals_referrer_idx on "better_supabase"."referrals" ("org_id", "referrer_id", "created_at" desc);
alter table "better_supabase"."referrals" enable row level security;
revoke all on "better_supabase"."referrals" from public, anon, authenticated;
grant select on "better_supabase"."referrals" to authenticated;
grant all on "better_supabase"."referrals" to service_role;
create policy bsb_referrals_read on "better_supabase"."referrals"
  for select to authenticated
  using (("org_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())));

-- Creates a referral code for a member (the caller by default). Making a code
-- for someone else needs referrals.manage, the own code referrals.write. code
-- is generated when omitted. The reward is paid in reward_unit on the ledger
-- when a referral qualifies. invitation_id ties the code to an invitation, so
-- accepting it attributes the referral.
create or replace function "better_supabase"."create_referral_code"(tenant uuid, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."referral_codes";
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_referrer is null then
    raise exception 'sign in to create a referral code' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.write'), false)))
    or (v_referrer is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false)))) then
    raise exception 'not allowed to create referral codes' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    raise exception 'a code is 4 to 32 letters or digits, and a reward needs a unit' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_referral_code.tenant is not null and coalesce(better_supabase.can('tenant', create_referral_code.tenant, 'referrals.manage'), false))) then
    raise exception 'rewards, limits and expiry on a code need referrals.manage' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  insert into "better_supabase"."referral_codes" ("org_id", "code", "referrer_id", "invitation_id", "reward_amount", "reward_unit", "max_uses", "expires_at")
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'code', v_row."code", 'referrerId', v_row."referrer_id", 'invitationId', v_row."invitation_id", 'rewardAmount', v_row."reward_amount"::text, 'rewardUnit', v_row."reward_unit", 'maxUses', v_row."max_uses", 'uses', v_row."uses", 'active', v_row."active", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_referral_code"(uuid, uuid, text, uuid, bigint, text, integer, timestamptz) to authenticated, service_role;

-- Attributes a referral without checking the caller: attribute_referral and
-- the invitation trigger call it. Attributing a user or an organization that
-- already has a referral returns that referral.
create or replace function "better_supabase"."referral_attribute"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_code "better_supabase"."referral_codes";
  v_ref "better_supabase"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."org_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."org_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "better_supabase"."referral_codes" x
  where x."org_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "better_supabase"."referrals" ("org_id", "code_id", "referrer_id", "referred_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "better_supabase"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."org_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."referral_attribute"(uuid, text, uuid, uuid, text) to service_role;

-- Attributes the user or organization that signed up with a code. Calling it
-- again for the same user or organization returns the first referral. Needs
-- referrals.write.
create or replace function "better_supabase"."attribute_referral"(tenant uuid, code text, referred_user uuid default null, referred_org uuid default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (attribute_referral.tenant is not null and coalesce(better_supabase.can('tenant', attribute_referral.tenant, 'referrals.write'), false))) then
    raise exception 'not allowed to attribute referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  return "better_supabase"."referral_attribute"(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$$;
revoke execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."attribute_referral"(uuid, text, uuid, uuid, text) to authenticated, service_role;

-- Marks the referral of a user or organization as qualified after the event
-- that earns the reward, such as its first paid invoice, and posts the reward
-- to the ledger when the code carries one: the reward expense account is
-- debited and the referrer's payable rewards account credited, once per
-- referral. source names what qualified it. Qualifying again returns the
-- referral. Needs referrals.manage.
create or replace function "better_supabase"."qualify_referral"(tenant uuid, referred_user uuid default null, referred_org uuid default null, source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."org_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."org_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "better_supabase"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."org_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."org_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."org_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "better_supabase"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    null;
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."org_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."qualify_referral"(uuid, uuid, uuid, text) to authenticated, service_role;

-- Voids a referral, for example after fraud or a refund. A reward already
-- posted is reversed on the ledger. Voiding a void referral returns it. Needs
-- referrals.manage.
create or replace function "better_supabase"."void_referral"(referral_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "better_supabase"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."org_id" is not null and coalesce(better_supabase.can('tenant', v_ref."org_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."org_id" is not null and coalesce(better_supabase.can('tenant', v_ref."org_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."org_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."org_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "better_supabase"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  null;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."org_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$$;
revoke execute on function "better_supabase"."void_referral"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_referral"(uuid, text) to authenticated, service_role;

-- An organization's referrals, newest first. filters is { referrer, status,
-- limit }. Needs referrals.read; without it a member sees the referrals of
-- their own codes.
create or replace function "better_supabase"."list_referrals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referrals" z
      where z."org_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referrals"(uuid, jsonb) to authenticated, service_role;

-- An organization's referral codes, newest first. filters is { referrer,
-- limit }. Needs referrals.read; without it a member sees their own codes.
create or replace function "better_supabase"."list_referral_codes"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referral_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_referral_codes.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'code', y."code", 'referrerId', y."referrer_id", 'invitationId', y."invitation_id", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'maxUses', y."max_uses", 'uses', y."uses", 'active', y."active", 'expiresAt', y."expires_at", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referral_codes" z
      where z."org_id" = list_referral_codes.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referral_codes"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."referral_codes" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (("org_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referral_codes" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referral_codes" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referral_codes" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."referrals" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (("org_id" in (select better_supabase.tenant_ids_with('referrals.read')) or "referrer_id" = (select auth.uid())))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."referrals" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."referrals" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."referrals" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_174_referrals.sql
-- better-supabase module: referrals
-- @bsb-block-data referrals
-- @bsb-hash sha256:ceb9afb90afb8e28f7810b7fb091d8845f340739a53570a530fd9a63c84d22f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
