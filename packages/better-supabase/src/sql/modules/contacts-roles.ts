import type { BlockSqlContext } from "../context.ts";
import type { PartyNames } from "./contacts-functions.ts";

import {
  CREDIT_BLOCKS,
  SUPPLIER_STATUSES,
} from "../../blocks/contacts/roles.ts";
import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { holderTypes } from "./qualifications-shared.ts";

export { PARTY_ROLES } from "../../blocks/contacts/roles.ts";

/** The role and commercial columns companies and people share. */
export const ROLE_COLUMNS = {
  roles: "roles",
  customerTermsId: "customer_terms_id",
  supplierTermsId: "supplier_terms_id",
  creditLimit: "credit_limit",
  creditCurrency: "credit_currency",
  creditBlock: "credit_block",
  supplierStatus: "supplier_status",
  language: "language",
} as const;

type RoleColumn = keyof typeof ROLE_COLUMNS;

export const ROLE_OPTIONAL: readonly RoleColumn[] = [
  "roles",
  "customerTermsId",
  "supplierTermsId",
  "creditLimit",
  "creditCurrency",
  "creditBlock",
  "supplierStatus",
  "language",
];

type PartyTable = "companies" | "people";

type Kind = "company" | "person";

const statusList = SUPPLIER_STATUSES.map((status) => sqlString(status)).join(
  ", ",
);

/** The currency comes before the limit, whose check reads it. */
const ROLE_ORDER: readonly RoleColumn[] = [
  "roles",
  "customerTermsId",
  "supplierTermsId",
  "creditCurrency",
  "creditLimit",
  "creditBlock",
  "supplierStatus",
  "language",
];

const blockList = CREDIT_BLOCKS.map((block) => sqlString(block)).join(", ");

/** What a language column holds: a BCP 47 tag such as `nl` or `pt-BR`. */
const LANGUAGE_PATTERN = "'^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'";

/** Each role column's type and checks, over its rendered name. */
function definitions(
  ctx: BlockSqlContext,
  table: PartyTable,
): readonly (readonly [RoleColumn, string])[] {
  const c = (logical: RoleColumn): string => ctx.col(table, logical);

  const types: Readonly<Record<RoleColumn, () => string>> = {
    roles: () => `text[] not null default '{}'::text[]`,
    customerTermsId: () =>
      `uuid references ${ctx.table("terms")} (${ctx.col("terms", "id")}) on delete set null`,
    supplierTermsId: () =>
      `uuid references ${ctx.table("terms")} (${ctx.col("terms", "id")}) on delete set null`,
    creditBlock: () => `text check (${c("creditBlock")} in (${blockList}))`,
    language: () => `text check (${c("language")} ~ ${LANGUAGE_PATTERN})`,
    creditCurrency: () => `text check (${c("creditCurrency")} ~ '^[A-Z]{3}$')`,
    creditLimit: () =>
      ctx.has(table, "creditCurrency")
        ? `bigint check (${c("creditLimit")} >= 0 and num_nulls(${c("creditLimit")}, ${c("creditCurrency")}) <> 1)`
        : `bigint check (${c("creditLimit")} >= 0)`,
    supplierStatus: () =>
      `text check (${c("supplierStatus")} in (${statusList}))`,
  };

  return ROLE_ORDER.filter((logical) => ctx.has(table, logical)).map(
    (logical) => [logical, types[logical]()] as const,
  );
}

/** The role columns inside `create table`, each on its own line. */
export function roleColumns(ctx: BlockSqlContext, table: PartyTable): string {
  return definitions(ctx, table)
    .map(([logical, type]) => `\n  ${ctx.col(table, logical)} ${type},`)
    .join("");
}

/** The indexes the role and supplier filters use. */
export function roleIndexes(ctx: BlockSqlContext, table: PartyTable): string {
  const t = ctx.table(table);
  const c = (logical: string): string => ctx.col(table, logical);
  const { name } = ctx.tableName(table);

  const roles = ctx.has(table, "roles")
    ? `\ncreate index if not exists ${ctx.naming.rename(`${name}_roles_idx`)} on ${t} using gin (${c("roles")});`
    : "";

  const status = ctx.has(table, "supplierStatus")
    ? `\ncreate index if not exists ${ctx.naming.rename(`${name}_supplier_status_idx`)} on ${t} (${c("tenant")}, ${c("supplierStatus")}) where ${c("supplierStatus")} is not null;`
    : "";

  const terms = (["customerTermsId", "supplierTermsId"] as const)
    .filter((logical) => ctx.has(table, logical))
    .map(
      (logical) =>
        `\ncreate index if not exists ${ctx.naming.rename(`${name}_${ROLE_COLUMNS[logical]}_idx`)} on ${t} (${c(logical)}) where ${c(logical)} is not null;`,
    )
    .join("");

  return `${roles}${status}${terms}`;
}

/**
 * ` || jsonb_build_object(...)` with the role columns of row `alias` under
 * fixed keys, the credit limit as text (ADR 0037); empty without them.
 */
export function roleJson(
  ctx: BlockSqlContext,
  table: PartyTable,
  alias: string,
): string {
  const pairs = definitions(ctx, table).map(([logical]) => {
    const value = `${alias}.${ctx.col(table, logical)}`;

    return `'${ROLE_COLUMNS[logical]}', ${logical === "creditLimit" ? `${value}::text` : value}`;
  });

  return pairs.length === 0
    ? ""
    : ` || jsonb_build_object(${pairs.join(", ")})`;
}

/**
 * PL/pgSQL that refuses payment terms or a credit limit that the columns would
 * reject, before the write: terms are 0 to 3650 days, a limit is whole minor
 * units with a three-letter currency.
 */
export function termsChecks(
  ctx: BlockSqlContext,
  table: PartyTable,
  attrs: string,
  tenant: string,
): string {
  const value = (key: string): string => `${attrs} ->> ${sqlString(key)}`;
  const has = (key: string): string => `${attrs} ? ${sqlString(key)}`;

  const invalid = fail(
    "PARTY_TERMS_INVALID",
    "a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR",
    "22023",
  );

  const termsOf = (key: string): string =>
    `${value(key)} is not null and not exists (select 1 from ${ctx.table("terms")} pt where pt.${ctx.col("terms", "id")}::text = ${value(key)} and pt.${ctx.col("terms", "tenant")} = ${tenant})`;

  const checks = [
    ...(ctx.has(table, "customerTermsId") ? [termsOf("customerTermsId")] : []),
    ...(ctx.has(table, "supplierTermsId") ? [termsOf("supplierTermsId")] : []),
    ...(ctx.has(table, "creditBlock")
      ? [
          `${value("creditBlock")} is not null and lower(trim(${value("creditBlock")})) not in (${blockList})`,
        ]
      : []),
    ...(ctx.has(table, "language")
      ? [
          `${value("language")} is not null and nullif(trim(${value("language")}), '') is not null and trim(${value("language")}) !~ ${LANGUAGE_PATTERN}`,
        ]
      : []),
    ...(ctx.has(table, "creditLimit")
      ? [
          `${value("creditLimit")} is not null and ${value("creditLimit")} !~ '^[0-9]{1,18}$'`,
        ]
      : []),
    ...(ctx.has(table, "creditCurrency")
      ? [
          `${value("creditCurrency")} is not null and upper(trim(${value("creditCurrency")})) !~ '^[A-Z]{3}$'`,
        ]
      : []),
    ...(ctx.has(table, "creditLimit") && ctx.has(table, "creditCurrency")
      ? [
          `${has("creditLimit")} <> ${has("creditCurrency")}`,
          `${has("creditLimit")} and (${value("creditLimit")} is null) <> (nullif(trim(${value("creditCurrency")}), '') is null)`,
        ]
      : []),
  ];

  return checks
    .map(
      (check) => `
  if ${check} then
    ${invalid}
  end if;`,
    )
    .join("");
}

/** The tables of the kinds a call reaches, as `[kind, table]`. */
const KINDS: readonly (readonly [Kind, PartyTable])[] = [
  ["company", "companies"],
  ["person", "people"],
];

/**
 * PL/pgSQL that finds the active company or person `id` names: its kind, tenant
 * and name.
 */
export function lookup(names: PartyNames, id: string): string {
  const { t, c } = names;

  return KINDS.map(
    (
      [kind, table],
      index,
    ) => `${index === 0 ? "" : "\n  if v_kind is null then\n  "}  select ${sqlString(kind)}, x.${c(table, "tenant")}, x.${c(table, "name")} into v_kind, v_tenant, v_name
  from ${t(table)} x where x.${c(table, "id")} = ${id} and x.${c(table, "mergedInto")} is null;${index === 0 ? "" : "\n  end if;"}`,
  ).join("");
}

/**
 * `set_party_roles` and `set_supplier_status` over companies and people, and
 * `supplier_status_from_qualifications` when qualifications rates companies.
 * `row` is a party's row as jsonb.
 */
export function roleFunctions(
  ctx: BlockSqlContext,
  names: PartyNames,
  row: (kind: Kind, alias: string) => string,
): string {
  const withRoles = KINDS.some(([, table]) => ctx.has(table, "roles"));

  const withStatus = KINDS.some(([, table]) =>
    ctx.has(table, "supplierStatus"),
  );

  return `${withRoles ? setRoles(ctx, names, row) : ""}${withStatus ? setStatus(ctx, names, row) : ""}${fromQualifications(ctx, names)}`;
}

/** The `{ type, party }` a role call returns for the party in v_kind. */
function partyResult(
  names: PartyNames,
  row: (kind: Kind, alias: string) => string,
  id: string,
): string {
  return `case v_kind${KINDS.map(
    ([kind, table]) => `
    when ${sqlString(kind)} then (select jsonb_build_object('type', ${sqlString(kind)}, 'party', ${row(kind, "x")}) from ${names.t(table)} x where x.${names.c(table, "id")} = ${id})`,
  ).join("")}
  end`;
}

function setRoles(
  ctx: BlockSqlContext,
  names: PartyNames,
  row: (kind: Kind, alias: string) => string,
): string {
  const { t, c, fn } = names;
  const name = "set_party_roles";
  const party = `${name}.party`;

  const updates = KINDS.map(([kind, table]) => {
    const payload = `jsonb_build_object('organizationId', v_tenant, ${sqlString(kind === "company" ? "companyId" : "personId")}, ${party}, 'name', v_name)`;

    const body = ctx.has(table, "roles")
      ? `update ${t(table)} x set ${c(table, "roles")} = v_roles, ${c(table, "updatedAt")} = now()
    where x.${c(table, "id")} = ${party} and x.${c(table, "roles")} is distinct from v_roles;
    if found then
      ${ctx.record({ type: `${kind}.updated`, payload, subject: `'${kind === "company" ? "companies" : "persons"}/' || ${party}::text`, tenant: "v_tenant::text", audit: false })}
    end if;`
      : fail(
          "PARTY_FIELD_UNSUPPORTED",
          `this ${ctx.tableName(table).name} table has no roles column`,
          "22023",
        );

    return `
  ${kind === "company" ? "if" : "elsif"} v_kind = ${sqlString(kind)} then
    ${body}`;
  }).join("");

  return `
-- Sets the roles of a company or person (customer, supplier and so on),
-- sorted and without duplicates. Returns { type, party }.
create or replace function ${fn(name)}(party uuid, roles text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_tenant ${ctx.idType};
  v_name text;
  v_roles text[] := array(select distinct trim(r) from unnest(coalesce(${name}.roles, '{}'::text[])) r where nullif(trim(r), '') is not null order by 1);
begin
${lookup(names, party)}
  if v_kind is null then
    ${fail("PARTY_NOT_FOUND", "company or person not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${names.scope.can("v_tenant", names.write)}) then
    ${fail("PARTY_FORBIDDEN", "not allowed to change companies and people")}
  end if;
  if not (v_roles <@ ${names.roles}) then
    ${fail("PARTY_ROLES_INVALID", "unknown party role", "22023")}
  end if;${updates}
  end if;
  return ${partyResult(names, row, party)};
end;
$$;
${userGrant(`${fn(name)}(uuid, text[])`)}
`;
}

function setStatus(
  ctx: BlockSqlContext,
  names: PartyNames,
  row: (kind: Kind, alias: string) => string,
): string {
  const { t, c, fn } = names;
  const name = "set_supplier_status";
  const party = `${name}.party`;

  const record = (kind: Kind): string =>
    ctx.record({
      type: `${kind}.supplier_status_changed`,
      payload: `jsonb_build_object('organizationId', v_tenant, ${sqlString(kind === "company" ? "companyId" : "personId")}, ${party}, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason)`,
      subject: `'${kind === "company" ? "companies" : "persons"}/' || ${party}::text`,
      tenant: "v_tenant::text",
      audit: {
        category: "data",
        targetType: kind,
        recordId: `${party}::text`,
        targetLabel: "v_name",
        summary: `'supplier status of ' || v_name || ' set to ' || coalesce(v_status, 'none')`,
      },
    });

  const updates = KINDS.map(([kind, table]) => {
    const body = ctx.has(table, "supplierStatus")
      ? `select x.${c(table, "supplierStatus")} into v_previous from ${t(table)} x where x.${c(table, "id")} = ${party} for update;
    update ${t(table)} x set ${c(table, "supplierStatus")} = v_status, ${c(table, "updatedAt")} = now()
    where x.${c(table, "id")} = ${party} and x.${c(table, "supplierStatus")} is distinct from v_status;
    if found then
      ${record(kind)}
    end if;`
      : fail(
          "PARTY_FIELD_UNSUPPORTED",
          `this ${ctx.tableName(table).name} table has no supplier_status column`,
          "22023",
        );

    return `
  ${kind === "company" ? "if" : "elsif"} v_kind = ${sqlString(kind)} then
    ${body}`;
  }).join("");

  return `
-- Sets where a supplier stands: approved, conditional, blocked, or null for
-- not assessed. Needs contacts.approve_supplier. Returns { type, party }.
create or replace function ${fn(name)}(party uuid, status text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_tenant ${ctx.idType};
  v_name text;
  v_status text := nullif(trim(${name}.status), '');
  v_reason text := nullif(trim(${name}.reason), '');
  v_previous text;
begin
${lookup(names, party)}
  if v_kind is null then
    ${fail("PARTY_NOT_FOUND", "company or person not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${names.scope.can("v_tenant", names.approveSupplier)}) then
    ${fail("PARTY_FORBIDDEN", "not allowed to approve suppliers")}
  end if;
  if v_status is not null and v_status not in (${statusList}) then
    ${fail("PARTY_SUPPLIER_STATUS_INVALID", "a supplier status is approved, conditional or blocked", "22023")}
  end if;
  if length(v_reason) > 2000 then
    ${fail("PARTY_SUPPLIER_STATUS_INVALID", "a reason has at most 2000 characters", "22023")}
  end if;${updates}
  end if;
  return ${partyResult(names, row, party)};
end;
$$;
${userGrant(`${fn(name)}(uuid, text, text)`)}
`;
}

/** Whether `supplier_status_from_qualifications` renders. */
export function ratesSuppliers(ctx: BlockSqlContext): boolean {
  return (
    ctx.installed("qualifications") &&
    holderTypes(ctx.of("qualifications")).includes("company")
  );
}

function fromQualifications(ctx: BlockSqlContext, names: PartyNames): string {
  if (!ratesSuppliers(ctx)) {
    return "";
  }

  const { t, c, fn } = names;
  const name = "supplier_status_from_qualifications";
  const gaps = ctx.of("qualifications").fn("qualification_gaps");

  return `
-- The supplier status a company's qualifications give it: approved when the
-- gap report lists no missing or expired qualification for it, conditional
-- otherwise. Pass it to set_supplier_status to apply it.
create or replace function ${fn(name)}(party uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_gaps jsonb;
begin
  select x.${c("companies", "tenant")} into v_tenant from ${t("companies")} x
  where x.${c("companies", "id")} = ${name}.party and x.${c("companies", "mergedInto")} is null;
  if v_tenant is null then
    ${fail("PARTY_NOT_FOUND", "company not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${names.scope.can("v_tenant", names.read)}) then
    ${fail("PARTY_FORBIDDEN", "not allowed to read companies and people")}
  end if;
  v_gaps := ${gaps}(v_tenant, 'company', jsonb_build_object('holderId', ${name}.party::text));
  return case when exists (
    select 1 from jsonb_array_elements(v_gaps) g where g ->> 'status' in ('missing', 'expired')
  ) then 'conditional' else 'approved' end;
end;
$$;
${userGrant(`${fn(name)}(uuid)`)}
`;
}
