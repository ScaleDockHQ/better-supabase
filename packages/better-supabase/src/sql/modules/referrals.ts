import type { ReferralsEvents } from "../../blocks/referrals/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { schemaPreamble } from "../shared.ts";
import { referralFunctions } from "./referrals-functions.ts";
import {
  attributesInvitations,
  invitationReferralSql,
} from "./referrals-invitations.ts";
import { referralSql } from "./referrals-sql.ts";
import { referralTables } from "./referrals-tables.ts";

const REFERRAL = [
  "organizationId",
  "id",
  "codeId",
  "referrerId",
  "referredUserId",
  "referredOrganizationId",
  "status",
] as const;

const referral = { subject: "referrals", payload: [...REFERRAL] } as const;

const EVENTS: BlockSqlEvents<ReferralsEvents> = {
  "referral_code.created": {
    subject: "referral-codes",
    payload: ["organizationId", "id", "code", "referrerId", "invitationId"],
  },
  "referral.attributed": referral,
  "referral.qualified": referral,
  "referral.rewarded": {
    subject: "referrals",
    payload: [...REFERRAL, "amount", "unit"],
  },
  "referral.voided": referral,
};

const NAMES: BlockSqlNames = {
  entities: {
    referral_code: { table: "codes", singular: "referral_code", primary: true },
    referral: { table: "referrals", singular: "referral" },
  },
  events: EVENTS,
  hooks: [],
  options: ["invitations"],
  tables: {
    codes: {
      name: "referral_codes",
      app: {},
      lifecycle: { tenant: "tenant", user: "referrer", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code",
        referrer: "referrer_id",
        invitation: "invitation_id",
        rewardAmount: "reward_amount",
        rewardUnit: "reward_unit",
        maxUses: "max_uses",
        uses: "uses",
        active: "active",
        expiresAt: "expires_at",
        createdAt: "created_at",
      },
    },
    referrals: {
      name: "referrals",
      app: {},
      lifecycle: { tenant: "tenant", user: "referrer", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code_id",
        referrer: "referrer_id",
        referredUser: "referred_id",
        referredOrganization: "referred_organization_id",
        referredEmail: "referred_email",
        status: "status",
        rewardAmount: "reward_amount",
        rewardUnit: "reward_unit",
        qualifiedAt: "qualified_at",
        qualifiedBy: "qualified_by",
        rewardedAt: "rewarded_at",
        ledgerTransaction: "ledger_transaction_id",
        voidedAt: "voided_at",
        createdAt: "created_at",
      },
    },
  },
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const q = referralSql(ctx);

  return `${schemaPreamble(ctx)}${referralTables(q)}${referralFunctions(q)}${attributesInvitations(ctx) ? invitationReferralSql(ctx, q) : ""}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_referral_code",
      args: [
        "{id}",
        "uuid",
        "text",
        "uuid",
        "bigint",
        "text",
        "integer",
        "timestamptz",
      ],
      returns: "jsonb",
    },
    {
      name: "attribute_referral",
      args: ["{id}", "text", "uuid", "{id}", "text"],
      returns: "jsonb",
    },
    {
      name: "qualify_referral",
      args: ["{id}", "uuid", "{id}", "text"],
      returns: "jsonb",
    },
    { name: "void_referral", args: ["uuid", "text"], returns: "jsonb" },
    { name: "list_referrals", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_referral_codes", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

export const REFERRALS: BlockSqlDefinition = {
  name: "referrals",
  scopes: ["tenant"],
  title: "Referrals",
  description:
    "Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.",
  requires: ["memberships", "permissions", "ledger"],
  integrates: ["outbox", "audit", "invitations"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
