import type { CommissionSql } from "./commissions-sql.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable } from "../shared.ts";
import {
  COMMISSION_PLAN_KINDS,
  COMMISSION_STATEMENT_STATUSES,
  COMMISSION_STATUSES,
} from "./commissions-values.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The JSON a plan, an assignment, an entry or a statement reads as. */
export function commissionJson(k: CommissionSql): {
  readonly plan: (row: string) => string;
  readonly assignment: (row: string) => string;
  readonly entry: (row: string) => string;
  readonly statement: (row: string) => string;
} {
  const { p, a, c, s } = k;

  return {
    plan: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'name', ${row}.${p("name")}, 'kind', ${row}.${p("kind")}, 'rateBps', ${row}.${p("rateBps")}, 'tiers', ${row}.${p("tiers")}, 'archivedAt', ${row}.${p("archivedAt")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`,
    assignment: (row) =>
      `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'planId', ${row}.${a("plan")}, 'sellerId', ${row}.${a("seller")}, 'subjectType', ${row}.${a("subjectType")}, 'subjectId', ${row}.${a("subjectId")}, 'startsOn', ${row}.${a("startsOn")}, 'endsOn', ${row}.${a("endsOn")}, 'createdAt', ${row}.${a("createdAt")})`,
    entry: (row) =>
      `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'planId', ${row}.${c("plan")}, 'sellerId', ${row}.${c("seller")}, 'sourceType', ${row}.${c("sourceType")}, 'sourceId', ${row}.${c("sourceId")}, 'basis', ${row}.${c("basis")}::text, 'amount', ${row}.${c("amount")}::text, 'currency', ${row}.${c("currency")}, 'occurredOn', ${row}.${c("occurredOn")}, 'status', ${row}.${c("status")}, 'statementId', ${row}.${c("statement")}, 'ledgerTransactionId', ${row}.${c("ledgerTransaction")}, 'reversedAt', ${row}.${c("reversedAt")}, 'createdAt', ${row}.${c("createdAt")})`,
    statement: (row) =>
      `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'sellerId', ${row}.${s("seller")}, 'currency', ${row}.${s("currency")}, 'startsOn', ${row}.${s("startsOn")}, 'endsOn', ${row}.${s("endsOn")}, 'status', ${row}.${s("status")}, 'total', ${row}.${s("total")}::text, 'ledgerTransactionId', ${row}.${s("ledgerTransaction")}, 'finalizedAt', ${row}.${s("finalizedAt")}, 'paidAt', ${row}.${s("paidAt")}, 'paidBy', ${row}.${s("paidBy")}, 'createdAt', ${row}.${s("createdAt")})`,
  };
}

/** The four tables, their indexes and the read policies. */
export function commissionTables(k: CommissionSql): string {
  const { ctx, idType, plans, assignments, entries, statements, p, a, c, s } =
    k;

  const name = (table: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(table).name}_${suffix}`);

  const readPolicy = (table: string, tenant: string, own?: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(table),
        name: name(table, "read"),
        command: "select",
        roles: ["authenticated"],
        using:
          own === undefined
            ? ctx.scope.check(tenant, k.read)
            : `${ctx.scope.check(tenant, k.read)} or ${own} = (select auth.uid())`,
      }),
      { target: ctx.table(table) },
    );

  return `-- Commission plans (flat rate or marginal tiers), their assignments to sellers,
-- the commissions accrued from paid records and the statements that collect
-- a seller's commissions per period. Amounts are bigint minor units.
create table if not exists ${plans} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${idType} not null,
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("kind")} text not null check (${p("kind")} in (${list(COMMISSION_PLAN_KINDS)})),
  -- A flat plan's rate in basis points (100 is 1%).
  ${p("rateBps")} integer check (${p("rateBps")} between 0 and 10000),
  -- A tiered plan's marginal tiers: [{ "upTo": 100000, "bps": 500 }, { "upTo": null, "bps": 800 }].
  ${p("tiers")} jsonb check (${p("tiers")} is null or jsonb_typeof(${p("tiers")}) = 'array'),
  ${p("archivedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("id")}),
  check ((${p("kind")} = 'flat' and ${p("rateBps")} is not null and ${p("tiers")} is null)
    or (${p("kind")} = 'tiered' and ${p("rateBps")} is null and ${p("tiers")} is not null))
);
create index if not exists ${name("plans", "tenant_idx")} on ${plans} (${p("tenant")}, ${p("createdAt")} desc, ${p("id")} desc);
${lockTable(plans, { read: true })}
${readPolicy("plans", p("tenant"))}

create table if not exists ${assignments} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${idType} not null,
  ${a("plan")} uuid not null,
  ${a("seller")} uuid not null,
  -- A plan for one record, such as a customer, over the seller's own plan.
  ${a("subjectType")} text,
  ${a("subjectId")} text,
  ${a("startsOn")} date not null default current_date,
  ${a("endsOn")} date,
  ${a("createdAt")} timestamptz not null default now(),
  check ((${a("subjectType")} is null) = (${a("subjectId")} is null)),
  check (${a("endsOn")} is null or ${a("endsOn")} >= ${a("startsOn")}),
  foreign key (${a("tenant")}, ${a("plan")}) references ${plans} (${p("tenant")}, ${p("id")}) on delete cascade
);
create index if not exists ${name("assignments", "plan_idx")} on ${assignments} (${a("tenant")}, ${a("plan")});
create index if not exists ${name("assignments", "seller_idx")} on ${assignments} (${a("tenant")}, ${a("seller")}, ${a("startsOn")} desc);
${lockTable(assignments, { read: true })}
${readPolicy("assignments", a("tenant"), a("seller"))}

create table if not exists ${statements} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${idType} not null,
  ${s("seller")} uuid not null,
  ${s("currency")} text not null check (${s("currency")} ~ '^[A-Z]{3}$'),
  ${s("startsOn")} date not null,
  ${s("endsOn")} date not null,
  ${s("status")} text not null default 'open' check (${s("status")} in (${list(COMMISSION_STATEMENT_STATUSES)})),
  ${s("total")} bigint not null default 0,
  -- The ledger transaction that paid the statement out.
  ${s("ledgerTransaction")} uuid,
  ${s("finalizedAt")} timestamptz,
  ${s("paidAt")} timestamptz,
  ${s("paidBy")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  check (${s("endsOn")} >= ${s("startsOn")}),
  unique (${s("tenant")}, ${s("id")}),
  unique (${s("tenant")}, ${s("seller")}, ${s("currency")}, ${s("startsOn")})
);
create index if not exists ${name("statements", "range_idx")} on ${statements} (${s("tenant")}, ${s("endsOn")}, ${s("status")});
${lockTable(statements, { read: true })}
${readPolicy("statements", s("tenant"), s("seller"))}

create table if not exists ${entries} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${idType} not null,
  ${c("plan")} uuid not null,
  ${c("seller")} uuid not null,
  -- The record the commission was earned on, such as invoices and its id.
  ${c("sourceType")} text not null check (length(${c("sourceType")}) between 1 and 100),
  ${c("sourceId")} text not null check (length(${c("sourceId")}) between 1 and 200),
  -- What the percentage was taken of, and what it came to, in minor units.
  ${c("basis")} bigint not null check (${c("basis")} > 0),
  ${c("amount")} bigint not null check (${c("amount")} > 0),
  ${c("currency")} text not null check (${c("currency")} ~ '^[A-Z]{3}$'),
  ${c("occurredOn")} date not null,
  ${c("status")} text not null default 'accrued' check (${c("status")} in (${list(COMMISSION_STATUSES)})),
  ${c("statement")} uuid,
  ${c("ledgerTransaction")} uuid,
  ${c("reversedAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now(),
  unique (${c("tenant")}, ${c("sourceType")}, ${c("sourceId")}, ${c("seller")}),
  foreign key (${c("tenant")}, ${c("plan")}) references ${plans} (${p("tenant")}, ${p("id")}),
  foreign key (${c("tenant")}, ${c("statement")}) references ${statements} (${s("tenant")}, ${s("id")})
);
create index if not exists ${name("entries", "seller_idx")} on ${entries} (${c("tenant")}, ${c("seller")}, ${c("currency")}, ${c("occurredOn")});
create index if not exists ${name("entries", "statement_idx")} on ${entries} (${c("tenant")}, ${c("statement")});
create index if not exists ${name("entries", "plan_idx")} on ${entries} (${c("tenant")}, ${c("plan")});
${lockTable(entries, { read: true })}
${readPolicy("entries", c("tenant"), c("seller"))}
`;
}
