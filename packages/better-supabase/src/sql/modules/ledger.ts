import type { LedgerEvents } from "../../blocks/ledger/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, schemaPreamble } from "../shared.ts";
import { ledgerFunctions, ledgerTouch } from "./ledger-functions.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const ACCOUNT_PAYLOAD = [
  "organizationId",
  "id",
  "kind",
  "code",
  "unit",
  "holderType",
  "holderId",
] as const;

const TRANSACTION_PAYLOAD = [
  "organizationId",
  "id",
  "kind",
  "referenceType",
  "referenceId",
  "reverses",
  "entries",
] as const;

const HOLD_PAYLOAD = [
  "organizationId",
  "id",
  "accountId",
  "amount",
  "status",
  "transactionId",
] as const;

const EVENTS: BlockSqlEvents<LedgerEvents> = {
  "ledger_account.opened": {
    subject: "ledger-accounts",
    payload: ACCOUNT_PAYLOAD,
  },
  "ledger_account.closed": {
    subject: "ledger-accounts",
    payload: ACCOUNT_PAYLOAD,
  },
  "ledger_transaction.posted": {
    subject: "ledger-transactions",
    payload: TRANSACTION_PAYLOAD,
  },
  "ledger_transaction.reversed": {
    subject: "ledger-transactions",
    payload: TRANSACTION_PAYLOAD,
  },
  "ledger_hold.placed": { subject: "ledger-holds", payload: HOLD_PAYLOAD },
  "ledger_hold.captured": { subject: "ledger-holds", payload: HOLD_PAYLOAD },
  "ledger_hold.released": { subject: "ledger-holds", payload: HOLD_PAYLOAD },
};

const NAMES: BlockSqlNames = {
  entities: {
    ledger_account: {
      table: "accounts",
      singular: "ledger_account",
      primary: true,
      subject: {
        title: "name",
        permissions: { read: "read", write: "manage" },
      },
    },
    ledger_transaction: {
      table: "transactions",
      singular: "ledger_transaction",
    },
    ledger_hold: { table: "holds", singular: "ledger_hold" },
  },
  events: EVENTS,
  hooks: ["before_ledger_transaction_post", "after_ledger_transaction_post"],
  tables: {
    accounts: {
      name: "ledger_accounts",
      app: {},
      typed: ["kind"],
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        code: "code",
        name: "name",
        unit: "unit",
        scale: "scale",
        holderType: "holder_type",
        holderId: "holder_id",
        owner: "owner_id",
        allowNegative: "allow_negative",
        readPermission: "read_permission",
        managedBy: "managed_by",
        metadata: "metadata",
        closedAt: "closed_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    transactions: {
      name: "ledger_transactions",
      app: {},
      optional: ["memo"],
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        referenceType: "reference_type",
        referenceId: "reference_id",
        memo: "memo",
        key: "idempotency_key",
        reverses: "reverses",
        metadata: "metadata",
        effectiveAt: "effective_at",
        actor: "actor_id",
        createdAt: "created_at",
      },
    },
    entries: {
      name: "ledger_entries",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        transaction: "transaction_id",
        account: "account_id",
        amount: "amount",
        unit: "unit",
        createdAt: "created_at",
      },
    },
    balances: {
      name: "ledger_balances",
      app: {},
      optional: ["available", "updatedAt"],
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        account: "account_id",
        tenant: "tenant_id",
        balance: "balance",
        held: "held",
        available: "available",
        updatedAt: "updated_at",
      },
    },
    holds: {
      name: "ledger_holds",
      app: {},
      optional: [
        "referenceType",
        "referenceId",
        "expiresAt",
        "createdBy",
        "updatedAt",
      ],
      typed: ["status"],
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        account: "account_id",
        amount: "amount",
        status: "status",
        referenceType: "reference_type",
        referenceId: "reference_id",
        expiresAt: "expires_at",
        transaction: "transaction_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

/**
 * The ledger's tables and indexes, without policies or triggers. The module
 * renders them, and the upgrade steps of the modules that moved onto the ledger
 * (inventory, leave, invoices) run them before copying their old rows in.
 */
export function ledgerTables(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const transactions = ctx.table("transactions");
  const entries = ctx.table("entries");
  const balances = ctx.table("balances");
  const holds = ctx.table("holds");
  const a = (column: string): string => ctx.col("accounts", column);
  const t = (column: string): string => ctx.col("transactions", column);
  const e = (column: string): string => ctx.col("entries", column);
  const b = (column: string): string => ctx.col("balances", column);
  const h = (column: string): string => ctx.col("holds", column);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const idType = ctx.idType;

  const optional = (
    logical: string,
    column: string,
    definition: string,
    lead = "\n  ",
  ): string =>
    ctx.has(logical, column)
      ? `${lead}${ctx.col(logical, column)} ${definition}`
      : "";

  return `create table if not exists ${accounts} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${idType} not null,
  ${a("kind")} text not null check (${a("kind")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${a("code")} text not null check (length(${a("code")}) between 1 and 200),
  ${a("name")} text not null check (length(${a("name")}) between 1 and 200),
  -- An ISO 4217 code for money, or a custom unit such as item, days or points.
  ${a("unit")} text not null check (${a("unit")} ~ '^([A-Z]{3}|[a-z][a-z0-9_]{0,31})$'),
  -- Decimal places of a custom unit: amounts are integers, 150 at scale 2 is 1.5.
  ${a("scale")} smallint not null default 0 check (${a("scale")} between 0 and 6),
  ${a("holderType")} text,
  ${a("holderId")} text,
  -- The member the account belongs to, who can read it without a permission.
  ${a("owner")} uuid,
  ${a("allowNegative")} boolean not null default false,
  -- A permission key that also grants reading the account.
  ${a("readPermission")} text,
  -- The module that posts to the account; post_ledger_transaction refuses it.
  ${a("managedBy")} text,
  ${a("metadata")} jsonb not null default '{}'::jsonb,
  ${a("closedAt")} timestamptz,
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  unique (${a("tenant")}, ${a("code")}),
  check ((${a("holderType")} is null) = (${a("holderId")} is null))
);${appUniqueIndex(ctx, "accounts", ["tenant", "code"])}
create index if not exists ${name("accounts", "holder_idx")} on ${accounts} (${a("tenant")}, ${a("holderType")}, ${a("holderId")}) where ${a("holderType")} is not null;
create index if not exists ${name("accounts", "kind_idx")} on ${accounts} (${a("tenant")}, ${a("kind")});
create index if not exists ${name("accounts", "owner_idx")} on ${accounts} (${a("owner")}) where ${a("owner")} is not null;

create table if not exists ${transactions} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${idType} not null,
  ${t("kind")} text not null check (${t("kind")} ~ '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$'),
  ${t("referenceType")} text,
  ${t("referenceId")} text,${ctx.has("transactions", "memo") ? `\n  ${t("memo")} text check (${t("memo")} is null or length(${t("memo")}) <= 2000),` : ""}
  ${t("key")} text,
  ${t("reverses")} uuid references ${transactions} (${t("id")}) on delete restrict,
  ${t("metadata")} jsonb not null default '{}'::jsonb,
  ${t("effectiveAt")} timestamptz not null default now(),
  ${t("actor")} uuid,
  ${t("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${name("transactions", "key_idx")} on ${transactions} (${t("tenant")}, ${t("key")}) where ${t("key")} is not null;
create unique index if not exists ${name("transactions", "reverses_idx")} on ${transactions} (${t("reverses")}) where ${t("reverses")} is not null;
create index if not exists ${name("transactions", "reference_idx")} on ${transactions} (${t("tenant")}, ${t("referenceType")}, ${t("referenceId")}) where ${t("referenceType")} is not null;
create index if not exists ${name("transactions", "tenant_idx")} on ${transactions} (${t("tenant")}, ${t("effectiveAt")} desc);

create table if not exists ${entries} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${idType} not null,
  ${e("transaction")} uuid not null references ${transactions} (${t("id")}) on delete restrict,
  ${e("account")} uuid not null references ${accounts} (${a("id")}) on delete restrict,
  -- Signed, in the account's unit: the entries of a transaction sum to zero per unit.
  ${e("amount")} bigint not null check (${e("amount")} <> 0),
  ${e("unit")} text not null,
  ${e("createdAt")} timestamptz not null default now()
);
create index if not exists ${name("entries", "account_idx")} on ${entries} (${e("account")}, ${e("createdAt")} desc);
create index if not exists ${name("entries", "transaction_idx")} on ${entries} (${e("transaction")});

create table if not exists ${balances} (
  ${b("account")} uuid primary key references ${accounts} (${a("id")}) on delete cascade,
  ${b("tenant")} ${idType} not null,
  ${b("balance")} bigint not null default 0,
  -- The sum of the account's active holds.
  ${b("held")} bigint not null default 0 check (${b("held")} >= 0)${optional("balances", "available", `bigint generated always as (${b("balance")} - ${b("held")}) stored`, ",\n  ")}${optional("balances", "updatedAt", "timestamptz not null default now()", ",\n  ")}
);${appUniqueIndex(ctx, "balances", ["account"])}
create index if not exists ${name("balances", "tenant_idx")} on ${balances} (${b("tenant")});

create table if not exists ${holds} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${idType} not null,
  ${h("account")} uuid not null references ${accounts} (${a("id")}) on delete restrict,
  ${h("amount")} bigint not null check (${h("amount")} > 0),
  ${h("status")} text not null default 'active' check (${h("status")} in ('active', 'captured', 'released', 'expired')),${optional("holds", "referenceType", "text,")}${optional("holds", "referenceId", "text,")}${optional("holds", "expiresAt", "timestamptz,")}
  ${h("transaction")} uuid references ${transactions} (${t("id")}) on delete restrict,${optional("holds", "createdBy", "uuid,")}
  ${h("createdAt")} timestamptz not null default now()${optional("holds", "updatedAt", "timestamptz not null default now()", ",\n  ")}
);
create index if not exists ${name("holds", "account_idx")} on ${holds} (${h("account")}, ${h("status")});
create index if not exists ${name("holds", "transaction_idx")} on ${holds} (${h("transaction")}) where ${h("transaction")} is not null;${
    ctx.has("holds", "expiresAt")
      ? `\ncreate index if not exists ${name("holds", "expiry_idx")} on ${holds} (${h("expiresAt")}) where ${h("status")} = 'active' and ${h("expiresAt")} is not null;`
      : ""
  }
`;
}

/**
 * SQL that recomputes every balance of the ledger from its entries and active
 * holds, for the upgrade steps that copy rows in without the entry trigger.
 */
export function ledgerRebalance(ctx: BlockSqlContext): string {
  const b = (column: string): string => ctx.col("balances", column);
  const e = (column: string): string => ctx.col("entries", column);
  const h = (column: string): string => ctx.col("holds", column);

  return `insert into ${ctx.table("balances")} as x (${b("account")}, ${b("tenant")}, ${b("balance")}, ${b("held")})
select s.account, s.tenant, s.balance, coalesce((select sum(y.${h("amount")}) from ${ctx.table("holds")} y where y.${h("account")} = s.account and y.${h("status")} = 'active'), 0)
from (
  select z.${e("account")} as account, min(z.${e("tenant")}::text)::${ctx.idType} as tenant, sum(z.${e("amount")}) as balance
  from ${ctx.table("entries")} z group by z.${e("account")}
) s
on conflict (${b("account")}) do update set ${b("balance")} = excluded.${b("balance")}, ${b("held")} = excluded.${b("held")}${ledgerTouch(ctx)};`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const accounts = ctx.table("accounts");
  const transactions = ctx.table("transactions");
  const entries = ctx.table("entries");
  const balances = ctx.table("balances");
  const holds = ctx.table("holds");
  const a = (column: string): string => ctx.col("accounts", column);
  const t = (column: string): string => ctx.col("transactions", column);
  const e = (column: string): string => ctx.col("entries", column);
  const b = (column: string): string => ctx.col("balances", column);
  const h = (column: string): string => ctx.col("holds", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("ledger");
  const read = ctx.permission("read", permissions.read);

  const policyName = (logical: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_read`);

  const tables = ctx.manages
    ? `${ledgerTables(ctx)}
${lockModuleTable(ctx, "accounts", { read: true })}
create index if not exists ${sqlIdent(`${ctx.tableName("accounts").name}_read_permission_idx`)} on ${accounts} (${a("tenant")}, ${a("readPermission")}) where ${a("readPermission")} is not null;
-- The (tenant, permission) pairs of account read permissions the caller
-- holds, so the policy checks each pair once per statement, not per row.
create or replace function ${fn("ledger_read_grants")}()
returns table (tenant ${ctx.idType}, permission text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select p.tenant, p.permission from (
    select distinct x.${a("tenant")} as tenant, x.${a("readPermission")} as permission
    from ${accounts} x
    where x.${a("readPermission")} is not null and x.${a("tenant")} in (select ${ctx.scope.members()})
  ) p
  where ${ctx.scope.can("p.tenant", "p.permission")};
end;
$$;
revoke execute on function ${fn("ledger_read_grants")}() from public, anon;
grant execute on function ${fn("ledger_read_grants")}() to authenticated, service_role;
${renderPolicy(
  makePolicy({
    table: accounts,
    name: policyName("accounts"),
    command: "select",
    roles: ["authenticated"],
    using: `${ctx.scope.check(a("tenant"), read)}
    or ${a("owner")} = (select auth.uid())
    or (${a("tenant")}, ${a("readPermission")}) in (select g.tenant, g.permission from ${fn("ledger_read_grants")}() g)`,
  }),
  { drop: true, target: accounts },
)}
${lockModuleTable(ctx, "transactions", { read: true })}
${renderPolicy(
  makePolicy({
    table: transactions,
    name: policyName("transactions"),
    command: "select",
    roles: ["authenticated"],
    using: `${ctx.scope.check(t("tenant"), read)}
    or exists (select 1 from ${entries} y where y.${e("transaction")} = ${t("id")})`,
  }),
  { drop: true, target: transactions },
)}
${lockModuleTable(ctx, "entries", { read: true })}
${renderPolicy(makePolicy({ table: entries, name: policyName("entries"), command: "select", roles: ["authenticated"], using: `${e("account")} in (select y.${a("id")} from ${accounts} y)` }), { drop: true, target: entries })}
${lockModuleTable(ctx, "balances", { read: true })}
${renderPolicy(makePolicy({ table: balances, name: policyName("balances"), command: "select", roles: ["authenticated"], using: `${b("account")} in (select y.${a("id")} from ${accounts} y)` }), { drop: true, target: balances })}
${lockModuleTable(ctx, "holds", { read: true })}
${renderPolicy(makePolicy({ table: holds, name: policyName("holds"), command: "select", roles: ["authenticated"], using: `${h("account")} in (select y.${a("id")} from ${accounts} y)` }), { drop: true, target: holds })}

-- Entries and transactions are append-only: a reversal posts the opposite.
create or replace function ${fn("ledger_append_only")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  ${fail("LEDGER_APPEND_ONLY", "ledger entries and transactions can't be changed or deleted; post a reversal", "55000")}
end;
$$;
revoke execute on function ${fn("ledger_append_only")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("ledger_entries_append_only")} on ${entries};
create trigger ${ctx.trigger("ledger_entries_append_only")} before update or delete on ${entries}
  for each row execute function ${fn("ledger_append_only")}();
drop trigger if exists ${ctx.trigger("ledger_transactions_append_only")} on ${transactions};
create trigger ${ctx.trigger("ledger_transactions_append_only")} before update or delete on ${transactions}
  for each row execute function ${fn("ledger_append_only")}();

-- Keeps the account's balance and refuses to take an account that doesn't
-- allow it below zero (counting its holds).
create or replace function ${fn("ledger_apply_entry")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available bigint;
begin
  insert into ${balances} as x (${b("account")}, ${b("tenant")}, ${b("balance")})
  values (new.${e("account")}, new.${e("tenant")}, new.${e("amount")})
  on conflict (${b("account")}) do update set ${b("balance")} = x.${b("balance")} + excluded.${b("balance")}${ledgerTouch(ctx)}
  returning x.${b("balance")} - x.${b("held")} into v_available;
  if new.${e("amount")} < 0 and v_available < 0 and not exists (
    select 1 from ${accounts} y where y.${a("id")} = new.${e("account")} and y.${a("allowNegative")}
  ) then
    ${fail("LEDGER_INSUFFICIENT", "the account doesn't have enough available", "23514")}
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("ledger_apply_entry")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("ledger_entries_apply")} on ${entries};
create trigger ${ctx.trigger("ledger_entries_apply")} after insert on ${entries}
  for each row execute function ${fn("ledger_apply_entry")}();

-- At commit, the entries of each transaction sum to zero per unit.
create or replace function ${fn("ledger_check_balanced")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from ${entries} y where y.${e("transaction")} = new.${e("transaction")}
    group by y.${e("unit")} having sum(y.${e("amount")}) <> 0
  ) then
    ${fail("LEDGER_UNBALANCED", "the entries of a ledger transaction must sum to zero per unit", "23514")}
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("ledger_check_balanced")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("ledger_entries_balanced")} on ${entries};
create constraint trigger ${ctx.trigger("ledger_entries_balanced")} after insert on ${entries}
  deferrable initially deferred
  for each row execute function ${fn("ledger_check_balanced")}();
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
${ledgerFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  const id = "{id}";

  return [
    {
      name: "ledger_account_for",
      args: [
        id,
        "text",
        "text",
        "text",
        "text",
        "smallint",
        "text",
        "text",
        "uuid",
        "boolean",
        "text",
        "text",
        "jsonb",
      ],
      returns: "uuid",
    },
    {
      name: "ledger_post",
      args: [
        id,
        "text",
        "jsonb",
        "text",
        "text",
        "text",
        "text",
        "timestamptz",
        "jsonb",
        "uuid",
      ],
      returns: "uuid",
    },
    {
      name: "list_ledger_accounts",
      args: [id, "text", "text", "text", "integer"],
      returns: "jsonb",
    },
  ];
}

export const LEDGER: BlockSqlDefinition = {
  internal: [
    "ledger_account_for",
    "ledger_post",
    "ledger_hold",
    "ledger_capture",
    "ledger_release",
    "ledger_read_grants",
  ],
  name: "ledger",
  scopes: ["tenant"],
  title: "Ledger",
  description:
    "Double-entry accounts in a currency or a custom unit, balanced transactions, balances and holds. Credits, stock, leave balances and invoice payments post through it.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit"],
  before: "inventory",
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
