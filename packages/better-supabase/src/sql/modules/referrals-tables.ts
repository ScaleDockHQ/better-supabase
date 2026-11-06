import type { ReferralSql } from "./referrals-sql.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable } from "../shared.ts";
import { REFERRAL_STATUSES } from "./referrals-values.ts";

/** The JSON a code or a referral reads as. */
export function referralJson(q: ReferralSql): {
  readonly code: (row: string) => string;
  readonly referral: (row: string) => string;
} {
  const { k, r } = q;

  return {
    code: (row) =>
      `jsonb_build_object('id', ${row}.${k("id")}, 'organizationId', ${row}.${k("tenant")}, 'code', ${row}.${k("code")}, 'referrerId', ${row}.${k("referrer")}, 'invitationId', ${row}.${k("invitation")}, 'rewardAmount', ${row}.${k("rewardAmount")}::text, 'rewardUnit', ${row}.${k("rewardUnit")}, 'maxUses', ${row}.${k("maxUses")}, 'uses', ${row}.${k("uses")}, 'active', ${row}.${k("active")}, 'expiresAt', ${row}.${k("expiresAt")}, 'createdAt', ${row}.${k("createdAt")})`,
    referral: (row) =>
      `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'codeId', ${row}.${r("code")}, 'referrerId', ${row}.${r("referrer")}, 'referredUserId', ${row}.${r("referredUser")}, 'referredOrganizationId', ${row}.${r("referredOrganization")}, 'referredEmail', ${row}.${r("referredEmail")}, 'status', ${row}.${r("status")}, 'rewardAmount', ${row}.${r("rewardAmount")}::text, 'rewardUnit', ${row}.${r("rewardUnit")}, 'qualifiedAt', ${row}.${r("qualifiedAt")}, 'rewardedAt', ${row}.${r("rewardedAt")}, 'ledgerTransactionId', ${row}.${r("ledgerTransaction")}, 'createdAt', ${row}.${r("createdAt")})`,
  };
}

/** The `referral_codes` and `referrals` tables, with read policies. */
export function referralTables(q: ReferralSql): string {
  const { ctx, idType, codes, referrals, k, r, read } = q;

  const name = (table: string, suffix: string): string =>
    ctx.naming.rename(`${ctx.tableName(table).name}_${suffix}`);

  const readPolicy = (
    table: "codes" | "referrals",
    tenant: string,
    owner: string,
  ): string => {
    const target = table === "codes" ? codes : referrals;
    const check = ctx.scope.check(tenant, read);

    return renderPolicy(
      makePolicy({
        table: target,
        name: sqlIdent(`${ctx.tableName(table).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: `(${check} or ${owner} = (select auth.uid()))`,
      }),
      { target },
    );
  };

  return `
-- Referral codes and the referrals they bring. A code belongs to the member who
-- shares it, optionally to one invitation. Rewards are bigint minor units of a
-- ledger unit, posted once per referral.
create table if not exists ${codes} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${idType} not null,
  ${k("code")} text not null check (${k("code")} ~ '^[A-Z0-9]{4,32}$'),
  ${k("referrer")} uuid not null,
  -- The invitation the code was made for, so accepting it attributes the referral.
  ${k("invitation")} uuid,
  ${k("rewardAmount")} bigint not null default 0 check (${k("rewardAmount")} >= 0),
  ${k("rewardUnit")} text check (${k("rewardUnit")} is null or length(${k("rewardUnit")}) between 1 and 32),
  ${k("maxUses")} integer check (${k("maxUses")} is null or ${k("maxUses")} > 0),
  ${k("uses")} integer not null default 0,
  ${k("active")} boolean not null default true,
  ${k("expiresAt")} timestamptz,
  ${k("createdAt")} timestamptz not null default now(),
  unique (${k("tenant")}, ${k("code")}),
  unique (${k("tenant")}, ${k("id")}),
  check (${k("rewardAmount")} = 0 or ${k("rewardUnit")} is not null)
);
create index if not exists ${name("codes", "referrer_idx")} on ${codes} (${k("tenant")}, ${k("referrer")});
create unique index if not exists ${name("codes", "invitation_key")} on ${codes} (${k("tenant")}, ${k("invitation")}) where ${k("invitation")} is not null;
${lockTable(codes, { read: true })}
${readPolicy("codes", k("tenant"), k("referrer"))}

create table if not exists ${referrals} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${idType} not null,
  ${r("code")} uuid not null,
  ${r("referrer")} uuid not null,
  ${r("referredUser")} uuid,
  ${r("referredOrganization")} ${idType},
  ${r("referredEmail")} text check (${r("referredEmail")} is null or length(${r("referredEmail")}) <= 320),
  ${r("status")} text not null default 'attributed' check (${r("status")} in (${REFERRAL_STATUSES.map((status) => `'${status}'`).join(", ")})),
  -- The reward as the code promised it when the referral was attributed.
  ${r("rewardAmount")} bigint not null default 0 check (${r("rewardAmount")} >= 0),
  ${r("rewardUnit")} text,
  ${r("qualifiedAt")} timestamptz,
  ${r("qualifiedBy")} text,
  ${r("rewardedAt")} timestamptz,
  ${r("ledgerTransaction")} uuid,
  ${r("voidedAt")} timestamptz,
  ${r("createdAt")} timestamptz not null default now(),
  check (${r("referredUser")} is not null or ${r("referredOrganization")} is not null or ${r("referredEmail")} is not null),
  foreign key (${r("tenant")}, ${r("code")}) references ${codes} (${k("tenant")}, ${k("id")}) on delete cascade
);
create unique index if not exists ${name("referrals", "user_key")} on ${referrals} (${r("tenant")}, ${r("referredUser")}) where ${r("referredUser")} is not null;
create unique index if not exists ${name("referrals", "organization_key")} on ${referrals} (${r("tenant")}, ${r("referredOrganization")}) where ${r("referredOrganization")} is not null;
create index if not exists ${name("referrals", "code_idx")} on ${referrals} (${r("tenant")}, ${r("code")});
create index if not exists ${name("referrals", "referrer_idx")} on ${referrals} (${r("tenant")}, ${r("referrer")}, ${r("createdAt")} desc);
${lockTable(referrals, { read: true })}
${readPolicy("referrals", r("tenant"), r("referrer"))}
`;
}
