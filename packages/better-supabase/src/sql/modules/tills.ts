import type { TillsEvents } from "../../blocks/tills/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  accountingContributions,
  accountingSourcesSql,
} from "../accounting-sources-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { tillsAccountingSources } from "./tills-accounting.ts";
import { tillsCashFunctions } from "./tills-cash-functions.ts";
import { tillsFunctions } from "./tills-functions.ts";
import { tillsSql } from "./tills-sql.ts";
import {
  TILL_DEPOSIT_STATUSES,
  TILL_MOVEMENT_KINDS,
  TILL_SESSION_STATUSES,
} from "./tills-values.ts";

const till = {
  subject: "tills",
  payload: ["organizationId", "id", "name", "currency"],
} as const;

const session = {
  subject: "tills",
  payload: ["organizationId", "id", "tillId", "status"],
} as const;

const movement = {
  subject: "tills",
  payload: ["organizationId", "id", "sessionId", "kind", "amount"],
} as const;

const deposit = {
  subject: "tills",
  payload: [
    "organizationId",
    "id",
    "sessionId",
    "amount",
    "status",
    "bankTransactionId",
  ],
} as const;

const EVENTS: BlockSqlEvents<TillsEvents> = {
  "till.created": till,
  "till.updated": till,
  "till_session.opened": session,
  "till_session.closed": session,
  "till_movement.recorded": movement,
  "till_deposit.recorded": deposit,
  "till_deposit.reconciled": deposit,
};

const NAMES: BlockSqlNames = {
  entities: {
    till: {
      table: "tills",
      singular: "till",
      primary: true,
      subject: { title: "name", permissions: { read: "read", write: "write" } },
    },
    till_session: { table: "sessions", singular: "till_session" },
    till_movement: { table: "movements", singular: "till_movement" },
    till_count: { table: "counts", singular: "till_count" },
    till_deposit: { table: "deposits", singular: "till_deposit" },
  },
  events: EVENTS,
  hooks: [
    "before_till_session_open",
    "after_till_session_open",
    "before_till_session_close",
    "after_till_session_close",
    "before_till_deposit",
    "after_till_deposit",
  ],
  options: [],
  tables: {
    tills: {
      name: "tills",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        currency: "currency",
        account: "account_id",
        location: "location",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    sessions: {
      name: "till_sessions",
      app: {},
      lifecycle: { tenant: "tenant", user: "openedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        till: "till_id",
        status: "status",
        openingFloat: "opening_float",
        openedBy: "opened_by",
        openedAt: "opened_at",
        closedBy: "closed_by",
        closedAt: "closed_at",
        notes: "notes",
      },
    },
    movements: {
      name: "till_movements",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        session: "session_id",
        kind: "kind",
        amount: "amount",
        reason: "reason",
        reference: "reference",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    counts: {
      name: "till_counts",
      app: {},
      lifecycle: { tenant: "tenant", user: "countedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        session: "session_id",
        denominations: "denominations",
        expected: "expected_amount",
        counted: "counted_amount",
        variance: "variance_amount",
        countedBy: "counted_by",
        countedAt: "counted_at",
        entry: "entry_id",
        notes: "notes",
      },
    },
    deposits: {
      name: "till_deposits",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        session: "session_id",
        amount: "amount",
        depositedOn: "deposited_on",
        reference: "reference",
        status: "status",
        entry: "entry_id",
        bankTransaction: "bank_transaction_id",
        reconciledAt: "reconciled_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const sql = tillsSql(ctx);
  const { t, s, m, c, d } = sql;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  // A cascading foreign key, unless the parent is an adopted app table.
  const ref = (parent: string, id: string): string =>
    ctx.owns(parent)
      ? ` references ${ctx.table(parent)} (${id}) on delete cascade`
      : "";

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, sql.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  return `
-- A cash register or drawer. account_id is the accounting account that holds its
-- cash; without it the till books nothing in accounting. archived tills open no
-- sessions.
create table if not exists ${sql.tills} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("name")} text not null check (length(${t("name")}) between 1 and 100),
  ${t("currency")} text not null check (${t("currency")} ~ '^[A-Z]{3}$'),
  ${t("account")} uuid,
  ${t("location")} text check (${t("location")} is null or length(${t("location")}) <= 200),
  ${t("archivedAt")} timestamptz,
  ${t("createdAt")} timestamptz not null default now(),
  ${t("updatedAt")} timestamptz not null default now(),
  unique (${t("tenant")}, ${t("name")})
);${appKey("tills", "tenant_id", `${t("tenant")}, ${t("id")}`)}
${lockTable(sql.tills, { read: true })}
${readPolicy("tills", t("tenant"))}

-- One shift at a till, from the opening float to the closing count. A till has
-- at most one open session. Amounts are minor units of the till's currency.
create table if not exists ${sql.sessions} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("till")} uuid not null${ref("tills", t("id"))},
  ${s("status")} text not null default 'open' check (${s("status")} in (${list(TILL_SESSION_STATUSES)})),
  ${s("openingFloat")} bigint not null default 0 check (${s("openingFloat")} >= 0),
  ${s("openedBy")} uuid,
  ${s("openedAt")} timestamptz not null default now(),
  ${s("closedBy")} uuid,
  ${s("closedAt")} timestamptz,
  ${s("notes")} text check (${s("notes")} is null or length(${s("notes")}) <= 2000)
);${appKey("sessions", "tenant_id", `${s("tenant")}, ${s("id")}`)}
create index if not exists ${name("sessions", "opened_idx")} on ${sql.sessions} (${s("till")}, ${s("openedAt")} desc);
create unique index if not exists ${name("sessions", "open_key")} on ${sql.sessions} (${s("till")}) where ${s("status")} = 'open';
${lockTable(sql.sessions, { read: true })}
${readPolicy("sessions", s("tenant"))}

-- Cash that went into or out of the drawer during a session: cash sales and
-- refunds, and cash put in or taken out. The amount is above zero; the kind
-- gives the direction.
create table if not exists ${sql.movements} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("session")} uuid not null${ref("sessions", s("id"))},
  ${m("kind")} text not null check (${m("kind")} in (${list(TILL_MOVEMENT_KINDS)})),
  ${m("amount")} bigint not null check (${m("amount")} > 0),
  ${m("reason")} text check (${m("reason")} is null or length(${m("reason")}) <= 500),
  ${m("reference")} text check (${m("reference")} is null or length(${m("reference")}) <= 200),
  ${m("createdBy")} uuid,
  ${m("createdAt")} timestamptz not null default now()
);${appKey("movements", "tenant_id", `${m("tenant")}, ${m("id")}`)}
create index if not exists ${name("movements", "session_idx")} on ${sql.movements} (${m("session")}, ${m("createdAt")});
${lockTable(sql.movements, { read: true })}
${readPolicy("movements", m("tenant"))}

-- The end-of-day count of a session: what the drawer should hold, what was
-- counted (from denominations or a total) and the difference. entry_id is the
-- accounting entry that books a non-zero difference.
create table if not exists ${sql.counts} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("session")} uuid not null${ref("sessions", s("id"))},
  ${c("denominations")} jsonb,
  ${c("expected")} bigint not null,
  ${c("counted")} bigint not null check (${c("counted")} >= 0),
  ${c("variance")} bigint not null,
  ${c("countedBy")} uuid,
  ${c("countedAt")} timestamptz not null default now(),
  ${c("entry")} uuid,
  ${c("notes")} text check (${c("notes")} is null or length(${c("notes")}) <= 2000),
  unique (${c("session")})
);${appKey("counts", "tenant_id", `${c("tenant")}, ${c("id")}`)}
${lockTable(sql.counts, { read: true })}
${readPolicy("counts", c("tenant"))}

-- Counted cash taken to the bank. A deposit is pending until it is matched to a
-- bank transaction in the banking block, then reconciled.
create table if not exists ${sql.deposits} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("session")} uuid not null${ref("sessions", s("id"))},
  ${d("amount")} bigint not null check (${d("amount")} > 0),
  ${d("depositedOn")} date not null,
  ${d("reference")} text check (${d("reference")} is null or length(${d("reference")}) <= 200),
  ${d("status")} text not null default 'pending' check (${d("status")} in (${list(TILL_DEPOSIT_STATUSES)})),
  ${d("entry")} uuid,
  ${d("bankTransaction")} uuid,
  ${d("reconciledAt")} timestamptz,
  ${d("createdBy")} uuid,
  ${d("createdAt")} timestamptz not null default now()
);${appKey("deposits", "tenant_id", `${d("tenant")}, ${d("id")}`)}
create index if not exists ${name("deposits", "session_idx")} on ${sql.deposits} (${d("session")});
${lockTable(sql.deposits, { read: true })}
${readPolicy("deposits", d("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Tills: sessions with an opening float, cash movements, an end-of-day count
-- that books its difference, deposits to the bank and their reconciliation.
${tables(ctx)}
${tillsFunctions(ctx)}
${tillsCashFunctions(ctx)}${accountingSourcesSql(ctx, tillsAccountingSources(ctx))}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "create_till", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_till", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "list_tills", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "open_till_session",
      args: ["uuid", "bigint", "text"],
      returns: "jsonb",
    },
    { name: "get_till_session", args: ["uuid"], returns: "jsonb" },
    { name: "list_till_sessions", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "record_till_movement",
      args: ["uuid", "text", "bigint", "text", "text"],
      returns: "jsonb",
    },
    { name: "close_till_session", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "deposit_till_cash", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "reconcile_till_deposit",
      args: ["uuid", "uuid"],
      returns: "jsonb",
    },
  ];
}

export const TILLS: BlockSqlDefinition = {
  name: "tills",
  scopes: ["tenant"],
  title: "Tills",
  description:
    "Till sessions with an opening float, cash in and out, end-of-day counts that book their difference in accounting, and cash deposits that reconcile to bank transactions.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["accounting", "banking", "outbox", "audit"],
  contributes: {
    accounting: (own) =>
      accountingContributions(own, tillsAccountingSources(own)),
  },
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
