-- better-supabase module: referrals
-- @bsb-block referrals@1 managed
-- @bsb-hash sha256:050ec3d93d8a782e5bfb8c46da1efc50adb304b6a08d58e1432f80d80a1c8bca
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

-- An organization's referrals, newest first. filters is { referrer (a value or
-- a list), status (a value or a list), sort, direction, facet, count, limit,
-- after, offset, paged, total, totalCap } (ADR 0749). Needs referrals.read;
-- without it a member sees the referrals of their own codes.
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
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'referrer') then
      raise exception 'facet is one of status, referrer' using errcode = '22023', hint = 'REFERRAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'referrer' then (x."referrer_id")::text end) as v
      from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt') then
    raise exception 'sort is one of createdAt' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'codeId', x."code_id", 'referrerId', x."referrer_id", 'referredUserId', x."referred_id", 'referredOrganizationId', x."referred_organization_id", 'referredEmail', x."referred_email", 'status', x."status", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'qualifiedAt', x."qualified_at", 'rewardedAt', x."rewarded_at", 'ledgerTransactionId', x."ledger_transaction_id", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."referrals" x
      where x."tenant_id" = list_referrals.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_referrals"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_referrals"(uuid, jsonb) to authenticated, service_role;

-- An organization's referral codes, newest first. filters is { referrer (a
-- value or a list), sort, direction, facet, count, limit, after, offset, paged,
-- total, totalCap } (ADR 0749). Needs referrals.read; without it a member sees
-- their own codes.
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
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('referrer') then
      raise exception 'facet is one of referrer' using errcode = '22023', hint = 'REFERRAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'referrer' then (x."referrer_id")::text end) as v
      from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt') then
    raise exception 'sort is one of createdAt' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'referrerId', x."referrer_id", 'invitationId', x."invitation_id", 'rewardAmount', x."reward_amount"::text, 'rewardUnit', x."reward_unit", 'maxUses', x."max_uses", 'uses', x."uses", 'active', x."active", 'expiresAt', x."expires_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."referral_codes" x
      where x."tenant_id" = list_referral_codes.tenant
        and (v_all or x."referrer_id" = (select auth.uid()))
        and (not (v_filters -> 'referrer' is not null and jsonb_typeof(v_filters -> 'referrer') <> 'null' and not (jsonb_typeof(v_filters -> 'referrer') = 'array' and jsonb_array_length(v_filters -> 'referrer') = 0)) or x."referrer_id" = any((case when jsonb_typeof(v_filters -> 'referrer') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'referrer')) else array[v_filters ->> 'referrer'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
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
