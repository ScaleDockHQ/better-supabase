import type { ConsentsEvents } from "../../blocks/consents/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { consentsFunctions } from "./consents-functions.ts";
import {
  consentsSignalFunctions,
  consentsSignalTables,
} from "./consents-signals.ts";
import {
  CONSENT_STATUSES,
  consentsSql,
  GIVEN_BY,
  LEGAL_BASES,
} from "./consents-sql.ts";

const CONSENT_PAYLOAD = [
  "organizationId",
  "consentId",
  "purposeId",
  "purposeKey",
  "subjectType",
  "subjectId",
  "status",
  "givenBy",
] as const;

const PURPOSE_PAYLOAD = [
  "organizationId",
  "purposeId",
  "key",
  "version",
] as const;

const consent = { subject: "consents", payload: CONSENT_PAYLOAD } as const;

const purpose = {
  subject: "consent-purposes",
  payload: PURPOSE_PAYLOAD,
} as const;

const EVENTS: BlockSqlEvents<ConsentsEvents> = {
  "consent.granted": consent,
  "consent.refused": consent,
  "consent.withdrawn": consent,
  "consent.expired": consent,
  "consent_purpose.created": purpose,
  "consent_purpose.updated": purpose,
  "consent_signal.recorded": {
    subject: "consent-signals",
    payload: ["organizationId", "signalId", "kind", "subjectType", "subjectId"],
  },
  "consent_receipt.issued": {
    subject: "consent-receipts",
    payload: [
      "organizationId",
      "receiptId",
      "consentId",
      "status",
      "subjectType",
      "subjectId",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    consent: { table: "consents", singular: "consent", primary: true },
    consent_purpose: { table: "purposes", singular: "consent_purpose" },
  },
  events: EVENTS,
  hooks: [
    "before_consent_record",
    "after_consent_record",
    "before_consent_withdraw",
    "after_consent_withdraw",
  ],
  options: [],
  tables: {
    purposes: {
      name: "consent_purposes",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        title: "title",
        description: "description",
        legalBasis: "legal_basis",
        version: "version",
        requiresSignature: "requires_signature",
        validMonths: "valid_months",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      app: {},
      optional: ["description", "updatedAt"],
      typed: ["legalBasis"],
    },
    consents: {
      name: "consents",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        purpose: "purpose_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        givenBy: "given_by",
        givenByContact: "given_by_contact_id",
        givenByUser: "given_by_user_id",
        status: "status",
        scope: "scope",
        grantedAt: "granted_at",
        validUntil: "valid_until",
        withdrawnAt: "withdrawn_at",
        withdrawnReason: "withdrawn_reason",
        signature: "signature_id",
        submission: "submission_id",
        attachment: "attachment_id",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      app: {},
      optional: [
        "scope",
        "withdrawnReason",
        "signature",
        "submission",
        "attachment",
        "createdBy",
      ],
      typed: ["givenBy", "status"],
    },
    signals: {
      name: "consent_signals",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        kind: "kind",
        raw: "raw",
        parsed: "parsed",
        consents: "consent_ids",
        createdBy: "created_by",
        receivedAt: "received_at",
      },
      app: {},
    },
    receipts: {
      name: "consent_receipts",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        consent: "consent_id",
        status: "status",
        receipt: "receipt",
        digest: "digest",
        issuedAt: "issued_at",
      },
      app: {},
    },
  },
};

const quoted = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = consentsSql(ctx);
  const { p, c, has, purposes, consents } = q;

  const name = (table: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(table).name}_${suffix}`);

  const optional = (
    table: "purposes" | "consents",
    column: string,
    definition: (name: string) => string,
  ): string =>
    has(table, column) ? `  ${definition(ctx.col(table, column))},\n` : "";

  const canSubject = ctx.of("subjects").fn("can_subject");

  return `create table if not exists ${purposes} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  -- Null for a system purpose every organization uses.
  ${p("tenant")} ${ctx.idType},
  ${p("key")} text not null check (${p("key")} ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  ${p("title")} text not null check (length(${p("title")}) between 1 and 200),
${optional("purposes", "description", (x) => `${x} text check (${x} is null or length(${x}) <= 4000)`)}  ${p("legalBasis")} text not null default 'consent' check (${p("legalBasis")} in (${quoted(LEGAL_BASES)})),
  ${p("version")} text not null default '1' check (length(${p("version")}) between 1 and 40),
  ${p("requiresSignature")} boolean not null default false,
  ${p("validMonths")} integer check (${p("validMonths")} is null or ${p("validMonths")} between 1 and 1200),
  ${p("archivedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now()${has("purposes", "updatedAt") ? `,\n  ${p("updatedAt")} timestamptz not null default now()` : ""}
);
create unique index if not exists ${name("purposes", "key_idx")} on ${purposes} (${p("tenant")}, ${p("key")}, ${p("version")}) nulls not distinct;
${lockTable(purposes, { read: true })}
${renderPolicy(makePolicy({ table: purposes, name: name("purposes", "read"), command: "select", roles: ["authenticated"], using: `${p("tenant")} is null or ${p("tenant")} in (select ${ctx.scope.members()})` }), { drop: true, target: purposes })}
create table if not exists ${consents} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("purpose")} uuid not null references ${purposes} (${p("id")}) on delete restrict,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("givenBy")} text not null default 'self' check (${c("givenBy")} in (${quoted(GIVEN_BY)})),
  -- The contact person who decided for the record, when a representative did.
  ${c("givenByContact")} uuid,
  ${c("givenByUser")} uuid,
  ${c("status")} text not null check (${c("status")} in (${quoted(CONSENT_STATUSES)})),
${optional("consents", "scope", (x) => `${x} jsonb not null default '{}'::jsonb check (jsonb_typeof(${x}) = 'object')`)}  -- When the decision was made, for a refusal too.
  ${c("grantedAt")} timestamptz not null default now(),
  ${c("validUntil")} timestamptz,
  ${c("withdrawnAt")} timestamptz,
${optional("consents", "withdrawnReason", (x) => `${x} text check (${x} is null or length(${x}) <= 1000)`)}${optional("consents", "signature", (x) => `${x} uuid`)}${optional("consents", "submission", (x) => `${x} uuid`)}${optional("consents", "attachment", (x) => `${x} uuid`)}${optional("consents", "createdBy", (x) => `${x} uuid`)}  ${c("createdAt")} timestamptz not null default now(),
  check (${c("givenBy")} <> 'representative' or ${c("givenByContact")} is not null),
  check (${c("status")} <> 'withdrawn' or ${c("withdrawnAt")} is not null)
);
-- One grant in force per record and purpose version.
create unique index if not exists ${name("consents", "granted_idx")} on ${consents} (${c("subjectType")}, ${c("subjectId")}, ${c("purpose")}) where ${c("status")} = 'granted';
create index if not exists ${name("consents", "subject_idx")} on ${consents} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("createdAt")} desc);
create index if not exists ${name("consents", "purpose_idx")} on ${consents} (${c("purpose")});
create index if not exists ${name("consents", "expiry_idx")} on ${consents} (${c("validUntil")}) where ${c("status")} = 'granted' and ${c("validUntil")} is not null;
${lockTable(consents, { read: true })}
${renderPolicy(makePolicy({ table: consents, name: name("consents", "read"), command: "select", roles: ["authenticated"], using: `(${ctx.scope.check(c("tenant"), q.read)} and ${canSubject}(${c("subjectType")}, ${c("subjectId")}, 'read')) or ${c("givenByUser")} = (select auth.uid())` }), { drop: true, target: consents })}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Consent per record and purpose: what an organization asks consent for, each
-- decision with who made it and its evidence, withdrawals and expiry.
${tables(ctx)}
${consentsSignalTables(ctx, consentsSql(ctx))}
${consentsFunctions(ctx)}
${consentsSignalFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_consent_purpose",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "text",
        "boolean",
        "integer",
      ],
      returns: "jsonb",
    },
    { name: "archive_consent_purpose", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_consent_purposes",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "record_consent",
      args: [
        "text",
        "text",
        "text",
        "text",
        "text",
        "uuid",
        "timestamptz",
        "jsonb",
        "jsonb",
      ],
      returns: "jsonb",
    },
    { name: "withdraw_consent", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "consent_active",
      args: ["text", "text", "text"],
      returns: "boolean",
    },
    {
      name: "list_consents",
      args: ["text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "expire_consents", args: [], returns: "integer" },
    {
      name: "record_consent_signal",
      args: ["text", "text", "text", "text", "text[]", "uuid"],
      returns: "jsonb",
    },
    { name: "list_consent_signals", args: ["text", "text"], returns: "jsonb" },
    { name: "issue_consent_receipt", args: ["uuid"], returns: "jsonb" },
    { name: "list_consent_receipts", args: ["text", "text"], returns: "jsonb" },
  ];
}

export const CONSENTS: BlockSqlDefinition = {
  internal: ["parse_tc_string", "parse_gpp_string"],
  name: "consents",
  scopes: ["tenant"],
  title: "Consents",
  description:
    "Consent per record and purpose: the purposes an organization asks consent for with their lawful basis and version, each decision with who made it (the person or a representative) and its signature, form or file as evidence, withdrawals and expiry. consent_active() answers whether processing may go ahead.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: [
    "contacts",
    "relations",
    "guests",
    "signatures",
    "forms",
    "attachments",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Consent signals (Sec-GPC, TCF v2.2, GPP) and consent receipts. New tables and functions only; the module file creates them.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
