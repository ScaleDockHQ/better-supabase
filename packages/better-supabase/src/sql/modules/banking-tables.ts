import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, lockTable } from "../shared.ts";
import {
  bankingSql,
  linked,
  MATCH_TARGETS,
  STATEMENT_FORMATS,
  TRANSACTION_STATUSES,
} from "./banking-sql.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The banking tables: accounts, rules, statements, transactions, matches. */
export function bankingTables(ctx: BlockSqlContext): string {
  const q = bankingSql(ctx);
  const { a, s, t, m, r } = q;
  const accounting = linked(ctx, "accounting");
  const attachments = linked(ctx, "attachments");

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, q.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const ref = (
    owner: BlockSqlContext | undefined,
    table: string,
    action: string,
  ): string =>
    owner?.owns(table)
      ? ` references ${owner.table(table)} (${owner.col(table, "id")}) on delete ${action}`
      : "";

  return `
create table if not exists ${q.accounts} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("name")} text not null check (length(${a("name")}) between 1 and 200),
  -- Upper case without spaces; save_bank_account checks the ISO 13616 digits.
  ${a("iban")} text check (${a("iban")} is null or ${a("iban")} ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  ${a("bic")} text check (${a("bic")} is null or ${a("bic")} ~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$'),
  ${a("currency")} char(3) not null check (${a("currency")} ~ '^[A-Z]{3}$'),
  -- The accounting journal the account's money moves through.
  ${a("journal")} uuid${ref(accounting, "journals", "set null")},
  ${a("archivedAt")} timestamptz,
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  unique (${a("tenant")}, ${a("id")})
);${addExtraColumns(q.accounts, q.extras)}${appKey("accounts", "tenant_id", `${a("tenant")}, ${a("id")}`)}
create unique index if not exists ${name("accounts", "iban_key")} on ${q.accounts} (${a("tenant")}, ${a("iban")}) where ${a("iban")} is not null;
create index if not exists ${name("accounts", "tenant_idx")} on ${q.accounts} (${a("tenant")}, ${a("name")});
create index if not exists ${name("accounts", "journal_idx")} on ${q.accounts} (${a("journal")}) where ${a("journal")} is not null;
${lockTable(q.accounts, { read: true })}
${readPolicy("accounts", a("tenant"))}

create table if not exists ${q.rules} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("name")} text not null check (length(${r("name")}) between 1 and 200),
  -- A filter tree (ADR 0046) over the transaction: amount, currency,
  -- counterpartyName, counterpartyIban, remittance and the rest.
  ${r("conditions")} jsonb not null default '{"type":"group","combinator":"and","rules":[]}'::jsonb,
  -- The ledger account a match books against; without one the rule ignores
  -- the transaction.
  ${r("account")} uuid${ref(accounting, "accounts", "restrict")},
  -- The party the booked line carries.
  ${r("party")} uuid,
  ${r("dimensions")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${r("dimensions")}) = 'object'),
  -- Lower runs first.
  ${r("priority")} integer not null default 100,
  ${r("active")} boolean not null default true,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("id")})
);${appKey("rules", "tenant_id", `${r("tenant")}, ${r("id")}`)}
create index if not exists ${name("rules", "tenant_idx")} on ${q.rules} (${r("tenant")}, ${r("priority")}) where ${r("active")};
create index if not exists ${name("rules", "account_idx")} on ${q.rules} (${r("account")}) where ${r("account")} is not null;
${lockTable(q.rules, { read: true })}
${readPolicy("rules", r("tenant"))}

create table if not exists ${q.statements} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("account")} uuid not null,
  -- The bank's statement id; an import with the same reference adds to it.
  ${s("reference")} text check (${s("reference")} is null or length(${s("reference")}) between 1 and 200),
  ${s("fromOn")} date,
  ${s("untilOn")} date,
  -- Minor units of the account's currency.
  ${s("openingBalance")} bigint,
  ${s("closingBalance")} bigint,
  ${s("format")} text not null check (${s("format")} in (${list(STATEMENT_FORMATS)})),
  -- The file it was read from.
  ${s("attachment")} uuid${ref(attachments, "attachments", "set null")},
  ${s("importedBy")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  unique (${s("tenant")}, ${s("id")}),
  check (${s("fromOn")} is null or ${s("untilOn")} is null or ${s("fromOn")} <= ${s("untilOn")}),
  foreign key (${s("tenant")}, ${s("account")}) references ${q.accounts} (${a("tenant")}, ${a("id")}) on delete cascade
);${appKey("statements", "tenant_id", `${s("tenant")}, ${s("id")}`)}
create unique index if not exists ${name("statements", "reference_key")} on ${q.statements} (${s("account")}, ${s("reference")}) where ${s("reference")} is not null;
create index if not exists ${name("statements", "parent_idx")} on ${q.statements} (${s("tenant")}, ${s("account")}, ${s("untilOn")});
create index if not exists ${name("statements", "attachment_idx")} on ${q.statements} (${s("attachment")}) where ${s("attachment")} is not null;
${lockTable(q.statements, { read: true })}
${readPolicy("statements", s("tenant"))}

create table if not exists ${q.transactions} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("account")} uuid not null,
  ${t("statement")} uuid,
  ${t("bookedOn")} date not null,
  ${t("valueOn")} date,
  -- Minor units, negative for money out.
  ${t("amount")} bigint not null check (${t("amount")} <> 0),
  ${t("currency")} char(3) not null check (${t("currency")} ~ '^[A-Z]{3}$'),
  ${t("counterpartyName")} text check (${t("counterpartyName")} is null or length(${t("counterpartyName")}) <= 500),
  ${t("counterpartyIban")} text check (${t("counterpartyIban")} is null or length(${t("counterpartyIban")}) <= 34),
  -- The unstructured remittance information.
  ${t("remittance")} text check (${t("remittance")} is null or length(${t("remittance")}) <= 2000),
  -- An ISO 11649 RF creditor reference or a national one, such as a Dutch
  -- betalingskenmerk.
  ${t("structuredReference")} text check (${t("structuredReference")} is null or length(${t("structuredReference")}) <= 100),
  ${t("endToEndId")} text check (${t("endToEndId")} is null or length(${t("endToEndId")}) <= 100),
  -- The bank's id of the entry; importing it again adds nothing.
  ${t("externalId")} text not null check (length(${t("externalId")}) between 1 and 200),
  ${t("status")} text not null default 'unmatched' check (${t("status")} in (${list(TRANSACTION_STATUSES)})),
  -- The bank rule that matched or ignored it.
  ${t("rule")} uuid,
  ${t("matchedAt")} timestamptz,
  ${t("matchedBy")} uuid,
  ${t("createdAt")} timestamptz not null default now(),
  ${t("updatedAt")} timestamptz not null default now(),
  unique (${t("tenant")}, ${t("id")}),
  unique (${t("account")}, ${t("externalId")}),
  foreign key (${t("tenant")}, ${t("account")}) references ${q.accounts} (${a("tenant")}, ${a("id")}) on delete cascade,
  foreign key (${t("tenant")}, ${t("statement")}) references ${q.statements} (${s("tenant")}, ${s("id")}) on delete set null (${t("statement")}),
  foreign key (${t("tenant")}, ${t("rule")}) references ${q.rules} (${r("tenant")}, ${r("id")}) on delete set null (${t("rule")})
);${appKey("transactions", "tenant_id", `${t("tenant")}, ${t("id")}`)}${appKey("transactions", "account_external", `${t("account")}, ${t("externalId")}`)}
create index if not exists ${name("transactions", "parent_idx")} on ${q.transactions} (${t("tenant")}, ${t("account")}, ${t("bookedOn")});
create index if not exists ${name("transactions", "status_idx")} on ${q.transactions} (${t("tenant")}, ${t("status")}, ${t("bookedOn")});
create index if not exists ${name("transactions", "statement_idx")} on ${q.transactions} (${t("tenant")}, ${t("statement")}) where ${t("statement")} is not null;
create index if not exists ${name("transactions", "rule_idx")} on ${q.transactions} (${t("tenant")}, ${t("rule")}) where ${t("rule")} is not null;
create index if not exists ${name("transactions", "iban_idx")} on ${q.transactions} (${t("tenant")}, ${t("counterpartyIban")}) where ${t("counterpartyIban")} is not null;
${lockTable(q.transactions, { read: true })}
${readPolicy("transactions", t("tenant"))}

create table if not exists ${q.matches} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("transaction")} uuid not null,
  ${m("targetType")} text not null check (${m("targetType")} in (${list(MATCH_TARGETS)})),
  ${m("targetId")} uuid not null,
  -- Minor units with the transaction's sign; a transaction's matches add up to
  -- its amount.
  ${m("amount")} bigint not null check (${m("amount")} <> 0),
  ${m("createdBy")} uuid,
  ${m("createdAt")} timestamptz not null default now(),
  foreign key (${m("tenant")}, ${m("transaction")}) references ${q.transactions} (${t("tenant")}, ${t("id")}) on delete cascade
);
create index if not exists ${name("matches", "parent_idx")} on ${q.matches} (${m("tenant")}, ${m("transaction")});
create index if not exists ${name("matches", "target_idx")} on ${q.matches} (${m("targetType")}, ${m("targetId")});
${lockTable(q.matches, { read: true })}
${readPolicy("matches", m("tenant"))}
`;
}
