import type { ReferralSql } from "./referrals-sql.ts";

import { sqlString } from "../../core/template.ts";
import { filterAny, listBody, listDeclare } from "../list-template.ts";
import { fail, serviceGrant, userGrant } from "../shared.ts";
import { referralJson } from "./referrals-tables.ts";

type ReferralEvent =
  | "referral.attributed"
  | "referral.qualified"
  | "referral.rewarded"
  | "referral.voided";

/** The ledger account of the reward expense or of a referrer's payable rewards. */
function rewardAccount(
  q: ReferralSql,
  kind: "expense" | "payable",
  referrer: string,
): string {
  const code =
    kind === "expense"
      ? `'referrals:expense:' || v_ref.${q.r("rewardUnit")}`
      : `'referrals:rewards:' || ${referrer}::text || ':' || v_ref.${q.r("rewardUnit")}`;

  return `${q.ledger.fn("ledger_account_for")}(v_ref.${q.r("tenant")}, '${kind}', ${code}, '${kind === "expense" ? "Referral rewards" : "Referral rewards payable"}', v_ref.${q.r("rewardUnit")}, 0::smallint, null, null, ${kind === "payable" ? referrer : "null"}, true, ${q.read}, 'referrals', null)`;
}

/** Codes, attribution, qualification and the reward posted on the ledger. */
export function referralFunctions(q: ReferralSql): string {
  const { idType, fn, codes, referrals, k, r, ledger } = q;
  const json = referralJson(q);

  const forbidden = (message: string): string =>
    fail("REFERRAL_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("REFERRAL_INVALID", message, "22023");

  const missing = fail("REFERRAL_NOT_FOUND", "no such referral", "P0002");

  const record = (type: ReferralEvent, rewarded = false): string =>
    q.ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_ref.${r("tenant")}, 'id', v_ref.${r("id")}, 'codeId', v_ref.${r("code")}, 'referrerId', v_ref.${r("referrer")}, 'referredUserId', v_ref.${r("referredUser")}, 'referredOrganizationId', v_ref.${r("referredOrganization")}, 'status', v_ref.${r("status")}${rewarded ? `, 'amount', v_ref.${r("rewardAmount")}::text, 'unit', v_ref.${r("rewardUnit")}` : ""})`,
      subject: `'referrals/' || v_ref.${r("id")}::text`,
      tenant: `v_ref.${r("tenant")}`,
      audit: {
        category: "data",
        targetType: "referral",
        recordId: `v_ref.${r("id")}::text`,
        summary: sqlString(type.replace("referral.", "referral ")),
      },
    });

  const referralList = {
    name: "list_referrals",
    from: referrals,
    alias: "x",
    where: [
      `x.${r("tenant")} = list_referrals.tenant`,
      `(v_all or x.${r("referrer")} = (select auth.uid()))`,
      filterAny("referrer", `x.${r("referrer")}`, "uuid"),
      filterAny("status", `x.${r("status")}`),
    ],
    keys: [
      { expr: `x.${r("createdAt")}`, dir: "desc", type: "timestamptz" },
      { expr: `x.${r("id")}`, dir: "asc", type: "uuid" },
    ],
    sorts: {
      createdAt: [
        { expr: `x.${r("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `x.${r("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { status: `x.${r("status")}`, referrer: `x.${r("referrer")}` },
    rowJson: json.referral("x"),
    defaultLimit: 100,
    maxLimit: 500,
    invalid,
  } as const;

  const codeList = {
    name: "list_referral_codes",
    from: codes,
    alias: "x",
    where: [
      `x.${k("tenant")} = list_referral_codes.tenant`,
      `(v_all or x.${k("referrer")} = (select auth.uid()))`,
      filterAny("referrer", `x.${k("referrer")}`, "uuid"),
    ],
    keys: [
      { expr: `x.${k("createdAt")}`, dir: "desc", type: "timestamptz" },
      { expr: `x.${k("id")}`, dir: "asc", type: "uuid" },
    ],
    sorts: {
      createdAt: [
        { expr: `x.${k("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `x.${k("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { referrer: `x.${k("referrer")}` },
    rowJson: json.code("x"),
    defaultLimit: 100,
    maxLimit: 500,
    invalid,
  } as const;

  return `
-- Creates a referral code for a member (the caller by default). Making a code
-- for someone else needs referrals.manage, the own code referrals.write. code
-- is generated when omitted. The reward is paid in reward_unit on the ledger
-- when a referral qualifies. invitation_id ties the code to an invitation, so
-- accepting it attributes the referral.
create or replace function ${fn("create_referral_code")}(tenant ${idType}, referrer_id uuid default null, code text default null, invitation_id uuid default null, reward_amount bigint default 0, reward_unit text default null, max_uses integer default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${codes};
  v_referrer uuid := coalesce(create_referral_code.referrer_id, auth.uid());
  v_code text := upper(coalesce(nullif(trim(create_referral_code.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
begin
  if v_referrer is null then
    ${forbidden("sign in to create a referral code")}
  end if;
  if not ${q.allowed("create_referral_code.tenant", q.write)}
    or (v_referrer is distinct from auth.uid() and not ${q.allowed("create_referral_code.tenant", q.manage)}) then
    ${forbidden("not allowed to create referral codes")}
  end if;
  if v_code !~ '^[A-Z0-9]{4,32}$' or coalesce(create_referral_code.reward_amount, 0) < 0
    or (coalesce(create_referral_code.reward_amount, 0) > 0 and nullif(trim(create_referral_code.reward_unit), '') is null) then
    ${invalid("a code is 4 to 32 letters or digits, and a reward needs a unit")}
  end if;
  if (coalesce(create_referral_code.reward_amount, 0) > 0 or create_referral_code.max_uses is not null or create_referral_code.expires_at is not null)
    and not ${q.allowed("create_referral_code.tenant", q.manage)} then
    ${forbidden("rewards, limits and expiry on a code need referrals.manage")}
  end if;
  insert into ${codes} (${k("tenant")}, ${k("code")}, ${k("referrer")}, ${k("invitation")}, ${k("rewardAmount")}, ${k("rewardUnit")}, ${k("maxUses")}, ${k("expiresAt")})
  values (create_referral_code.tenant, v_code, v_referrer, create_referral_code.invitation_id, coalesce(create_referral_code.reward_amount, 0),
    nullif(trim(create_referral_code.reward_unit), ''), create_referral_code.max_uses, create_referral_code.expires_at)
  returning * into v_row;
  ${q.ctx.record({
    type: "referral_code.created",
    payload: `jsonb_build_object('organizationId', v_row.${k("tenant")}, 'id', v_row.${k("id")}, 'code', v_row.${k("code")}, 'referrerId', v_row.${k("referrer")}, 'invitationId', v_row.${k("invitation")})`,
    subject: `'referral-codes/' || v_row.${k("id")}::text`,
    tenant: `v_row.${k("tenant")}`,
    audit: {
      category: "data",
      targetType: "referral_code",
      recordId: `v_row.${k("id")}::text`,
      targetLabel: `v_row.${k("code")}`,
      summary: "'created a referral code'",
    },
  })}
  return ${json.code("v_row")};
end;
$$;
${userGrant(`${fn("create_referral_code")}(${idType}, uuid, text, uuid, bigint, text, integer, timestamptz)`)}

-- Attributes a referral without checking the caller: attribute_referral and
-- the invitation trigger call it. Attributing a user or an organization that
-- already has a referral returns that referral.
create or replace function ${fn("referral_attribute")}(tenant ${idType}, code text, referred_user uuid default null, referred_org ${idType} default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_code ${codes};
  v_ref ${referrals};
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    ${invalid("name the referred user, organization or email")}
  end if;
  select * into v_ref from ${referrals} x
  where x.${r("tenant")} = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x.${r("referredUser")} = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x.${r("referredOrganization")} = referral_attribute.referred_org));
  if found then
    return ${json.referral("v_ref")};
  end if;
  select * into v_code from ${codes} x
  where x.${k("tenant")} = referral_attribute.tenant and x.${k("code")} = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code.${k("active")} or (v_code.${k("expiresAt")} is not null and v_code.${k("expiresAt")} < now())
    or (v_code.${k("maxUses")} is not null and v_code.${k("uses")} >= v_code.${k("maxUses")}) then
    ${fail("REFERRAL_CODE_INVALID", "the referral code is unknown, expired or used up", "P0002")}
  end if;
  if referral_attribute.referred_user = v_code.${k("referrer")} then
    ${fail("REFERRAL_SELF", "a member can't refer themselves", "22023")}
  end if;
  insert into ${referrals} (${r("tenant")}, ${r("code")}, ${r("referrer")}, ${r("referredUser")}, ${r("referredOrganization")}, ${r("referredEmail")}, ${r("rewardAmount")}, ${r("rewardUnit")})
  values (referral_attribute.tenant, v_code.${k("id")}, v_code.${k("referrer")}, referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code.${k("rewardAmount")}, v_code.${k("rewardUnit")})
  returning * into v_ref;
  update ${codes} x set ${k("uses")} = x.${k("uses")} + 1 where x.${k("id")} = v_code.${k("id")};
  ${record("referral.attributed")}
  return ${json.referral("v_ref")};
end;
$$;
${serviceGrant(`${fn("referral_attribute")}(${idType}, text, uuid, ${idType}, text)`)}

-- Attributes the user or organization that signed up with a code. Calling it
-- again for the same user or organization returns the first referral. Needs
-- referrals.write.
create or replace function ${fn("attribute_referral")}(tenant ${idType}, code text, referred_user uuid default null, referred_org ${idType} default null, referred_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("attribute_referral.tenant", q.write)} then
    ${forbidden("not allowed to attribute referrals")}
  end if;
  return ${fn("referral_attribute")}(attribute_referral.tenant, attribute_referral.code, attribute_referral.referred_user,
    attribute_referral.referred_org, attribute_referral.referred_email);
end;
$$;
${userGrant(`${fn("attribute_referral")}(${idType}, text, uuid, ${idType}, text)`)}

-- Marks the referral of a user or organization as qualified after the event
-- that earns the reward, such as its first paid invoice, and posts the reward
-- to the ledger when the code carries one: the reward expense account is
-- debited and the referrer's payable rewards account credited, once per
-- referral. source names what qualified it. Qualifying again returns the
-- referral. Needs referrals.manage.
create or replace function ${fn("qualify_referral")}(tenant ${idType}, referred_user uuid default null, referred_org ${idType} default null, source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref ${referrals};
  v_tx uuid;
begin
  if not ${q.allowed("qualify_referral.tenant", q.manage)} then
    ${forbidden("not allowed to qualify referrals")}
  end if;
  select * into v_ref from ${referrals} x
  where x.${r("tenant")} = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x.${r("referredUser")} = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x.${r("referredOrganization")} = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref.${r("status")} <> 'attributed' then
    return ${json.referral("v_ref")};
  end if;
  update ${referrals} x set ${r("status")} = 'qualified', ${r("qualifiedAt")} = now(), ${r("qualifiedBy")} = left(qualify_referral.source, 200)
  where x.${r("id")} = v_ref.${r("id")} returning * into v_ref;
  ${record("referral.qualified")}
  if v_ref.${r("rewardAmount")} > 0 then
    v_tx := ${ledger.fn("ledger_post")}(v_ref.${r("tenant")}, 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', ${rewardAccount(q, "expense", `v_ref.${r("referrer")}`)}, 'amount', (-v_ref.${r("rewardAmount")})::text),
        jsonb_build_object('account', ${rewardAccount(q, "payable", `v_ref.${r("referrer")}`)}, 'amount', v_ref.${r("rewardAmount")}::text)),
      'referrals', v_ref.${r("id")}::text, null, 'referral:' || v_ref.${r("id")}::text, null,
      jsonb_build_object('referrerId', v_ref.${r("referrer")}));
    update ${referrals} x set ${r("status")} = 'rewarded', ${r("rewardedAt")} = now(), ${r("ledgerTransaction")} = v_tx
    where x.${r("id")} = v_ref.${r("id")} returning * into v_ref;
    ${record("referral.rewarded", true)}
  end if;
  return ${json.referral("v_ref")};
end;
$$;
${userGrant(`${fn("qualify_referral")}(${idType}, uuid, ${idType}, text)`)}

-- Voids a referral, for example after fraud or a refund. A reward already
-- posted is reversed on the ledger. Voiding a void referral returns it. Needs
-- referrals.manage.
create or replace function ${fn("void_referral")}(referral_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_ref ${referrals};
begin
  select * into v_ref from ${referrals} x where x.${r("id")} = void_referral.referral_id for update;
  if not found or not ${q.allowed(`v_ref.${r("tenant")}`, q.read)} then
    ${missing}
  end if;
  if not ${q.allowed(`v_ref.${r("tenant")}`, q.manage)} then
    ${forbidden("not allowed to void referrals")}
  end if;
  if v_ref.${r("status")} = 'void' then
    return ${json.referral("v_ref")};
  end if;
  if v_ref.${r("ledgerTransaction")} is not null then
    perform ${ledger.fn("ledger_post")}(v_ref.${r("tenant")}, 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e.${ledger.col("entries", "account")}, 'amount', (-e.${ledger.col("entries", "amount")})::text) order by e.${ledger.col("entries", "createdAt")}, e.${ledger.col("entries", "id")})
        from ${ledger.table("entries")} e where e.${ledger.col("entries", "transaction")} = v_ref.${r("ledgerTransaction")}),
      'referrals', v_ref.${r("id")}::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref.${r("id")}::text, null,
      jsonb_build_object('reversal', true), v_ref.${r("ledgerTransaction")});
  end if;
  update ${referrals} x set ${r("status")} = 'void', ${r("voidedAt")} = now()
  where x.${r("id")} = v_ref.${r("id")} returning * into v_ref;
  ${record("referral.voided")}
  return ${json.referral("v_ref")};
end;
$$;
${userGrant(`${fn("void_referral")}(uuid, text)`)}

-- An organization's referrals, newest first. filters is { referrer (a value or
-- a list), status (a value or a list), sort, direction, facet, count, limit,
-- after, offset, paged, total, totalCap } (ADR 0749). Needs referrals.read;
-- without it a member sees the referrals of their own codes.
create or replace function ${fn("list_referrals")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := ${q.allowed("list_referrals.tenant", q.read)};
  ${listDeclare(referralList)}
begin
  ${listBody(referralList)}
end;
$$;
${userGrant(`${fn("list_referrals")}(${idType}, jsonb)`)}

-- An organization's referral codes, newest first. filters is { referrer (a
-- value or a list), sort, direction, facet, count, limit, after, offset, paged,
-- total, totalCap } (ADR 0749). Needs referrals.read; without it a member sees
-- their own codes.
create or replace function ${fn("list_referral_codes")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referral_codes.filters, '{}'::jsonb);
  v_all boolean := ${q.allowed("list_referral_codes.tenant", q.read)};
  ${listDeclare(codeList)}
begin
  ${listBody(codeList)}
end;
$$;
${userGrant(`${fn("list_referral_codes")}(${idType}, jsonb)`)}
`;
}
