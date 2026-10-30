import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlScope } from "../scope.ts";

import { sqlString } from "../../core/template.ts";
import { columnsObject, fail, pageSize, userGrant } from "../shared.ts";
import { recordMergeFunction } from "../subject-merge-sql.ts";
import { watchSql } from "../watch-sql.ts";
import { identityMergeMoves } from "./contacts-identities.ts";
import { personMergeMoves } from "./contacts-inbox.ts";
import { asText } from "./over-app.ts";

export interface PartyNames {
  /** The block's scope checks. */
  readonly scope: BlockSqlScope;
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  /** The `text[]` of company lifecycle stages; the first is the default. */
  readonly companyStages: string;
  /** The `text[]` of person lifecycle stages; the first is the default. */
  readonly personStages: string;
}

type Kind = "company" | "person";

/**
 * ` || jsonb_build_object('fields', ...)` with a company's extra columns
 * (`options.extraColumns`) for row `alias`; empty for people and without extra
 * columns.
 */
function extraFields(ctx: BlockSqlContext, kind: Kind, alias: string): string {
  if (kind !== "company") {
    return "";
  }

  const extras = ctx.extraColumns("companies");

  return extras.length === 0
    ? ""
    : ` || jsonb_build_object('fields', ${columnsObject(
        alias,
        extras.map((extra) => extra.name),
      )})`;
}

interface Field {
  /** The attrs key, camelCase. */
  readonly key: string;
  /** The logical column. */
  readonly column: string;
  /** SQL over `v` (the attrs value as text) that the column stores. */
  readonly value: (v: string) => string;
}

const text = (v: string): string => `nullif(trim(${v}), '')`;
const lower = (v: string): string => `lower(nullif(trim(${v}), ''))`;
const uuid = (v: string): string => `nullif(${v}, '')::uuid`;

const FIELDS: Readonly<Record<Kind, readonly Field[]>> = {
  company: [
    { key: "name", column: "name", value: text },
    { key: "domain", column: "domain", value: lower },
    { key: "website", column: "website", value: text },
    { key: "vatId", column: "vatId", value: text },
    { key: "lifecycle", column: "lifecycle", value: text },
    { key: "ownerId", column: "owner", value: uuid },
  ],
  person: [
    { key: "name", column: "name", value: text },
    { key: "email", column: "email", value: lower },
    { key: "phone", column: "phone", value: text },
    { key: "title", column: "title", value: text },
    { key: "lifecycle", column: "lifecycle", value: text },
    { key: "ownerId", column: "owner", value: uuid },
    { key: "userId", column: "user", value: uuid },
  ],
};

const SPEC = {
  company: {
    table: "companies",
    fn: "save_company",
    hook: "company",
    subject: "companies",
    idKey: "companyId",
    taken: ["PARTY_DOMAIN_TAKEN", "another company has this domain"],
  },
  person: {
    table: "people",
    fn: "save_person",
    hook: "person",
    subject: "persons",
    idKey: "personId",
    taken: ["PARTY_EMAIL_TAKEN", "another person has this email"],
  },
} as const;

/** The fields of `kind` whose column the table has. */
const fieldsOf = (ctx: BlockSqlContext, kind: Kind): readonly Field[] =>
  FIELDS[kind].filter((field) => ctx.has(SPEC[kind].table, field.column));

/** PL/pgSQL that refuses attrs keys of `kind` whose column the app maps to null. */
function unsupported(ctx: BlockSqlContext, kind: Kind, attrs: string): string {
  const { table } = SPEC[kind];

  return [
    ...FIELDS[kind].map((field) => [field.key, field.column] as const),
    ...(kind === "company" ? [["address", "address"] as const] : []),
  ]
    .filter(([, column]) => !ctx.has(table, column))
    .map(
      ([key, column]) => `
  if ${attrs} ->> ${sqlString(key)} is not null then
    ${fail("PARTY_FIELD_UNSUPPORTED", `this ${ctx.tableName(table).name} table has no ${column} column`, "22023")}
  end if;`,
    )
    .join("");
}

const guard = (
  scope: BlockSqlScope,
  tenant: string,
  permission: string,
  code: string,
): string =>
  `if not (auth.role() = 'service_role' or ${scope.can(tenant, permission)}) then
    ${fail(code, "not allowed to change companies and people")}
  end if;`;

function saveFunction(
  ctx: BlockSqlContext,
  names: PartyNames,
  kind: Kind,
): string {
  const spec = SPEC[kind];
  const { t, c } = names;
  const col = (logical: string): string => c(spec.table, logical);
  const fnName = spec.fn;
  const arg = (key: string): string => `${fnName}.attrs ->> ${sqlString(key)}`;
  const has = (key: string): string => `${fnName}.attrs ? ${sqlString(key)}`;
  const fields = fieldsOf(ctx, kind);
  const exists = (logical: string): boolean => ctx.has(spec.table, logical);
  const address = kind === "company" && exists("address");
  const owner = exists("owner");
  const stages = kind === "company" ? names.companyStages : names.personStages;
  // options.extraColumns adds columns to companies; people take custom fields.
  const extras = kind === "company" ? ctx.extraColumns("companies") : [];
  const table = t(spec.table);

  const extraValue = (ident: string): string =>
    `(jsonb_populate_record(null::${table}, ${fnName}.attrs)).${ident}`;

  // The lifecycle column can be the app's enum.
  const lifecycle = (value: string): string =>
    ctx.cast(spec.table, "lifecycle", value);

  const insertColumns = [
    col("tenant"),
    ...fields.map((field) => col(field.column)),
    ...(address ? [col("address")] : []),
    ...(exists("createdBy") ? [col("createdBy")] : []),
    ...extras.map((extra) => extra.ident),
  ];

  const insertValues = [
    `${fnName}.tenant`,
    ...fields.map((field) =>
      field.key === "lifecycle"
        ? lifecycle(`coalesce(${field.value(arg(field.key))}, (${stages})[1])`)
        : field.value(arg(field.key)),
    ),
    ...(address ? [`${fnName}.attrs -> 'address'`] : []),
    ...(exists("createdBy") ? ["auth.uid()"] : []),
    ...extras.map((extra) => extraValue(extra.ident)),
  ];

  const updates = [
    ...fields.map(
      (field) =>
        `${col(field.column)} = case when ${has(field.key)} then ${field.key === "name" || field.key === "lifecycle" ? `coalesce(${field.key === "lifecycle" ? lifecycle(field.value(arg(field.key))) : field.value(arg(field.key))}, x.${col(field.column)})` : field.value(arg(field.key))} else x.${col(field.column)} end`,
    ),
    ...(address
      ? [
          `${col("address")} = case when ${has("address")} then ${fnName}.attrs -> 'address' else x.${col("address")} end`,
        ]
      : []),
    ...extras.map(
      (extra) =>
        `${extra.ident} = case when ${has(extra.name)} then ${extraValue(extra.ident)} else x.${extra.ident} end`,
    ),
    `${col("updatedAt")} = now()`,
  ];

  const payload = `jsonb_build_object('organizationId', ${fnName}.tenant, ${sqlString(spec.idKey)}, v_id, 'name', v_row ->> ${sqlString(ctx.colName(spec.table, "name"))})`;
  const subject = `'${spec.subject}/' || v_id::text`;

  const watch = watchSql(ctx, {
    tenant: `${fnName}.tenant`,
    user: "v_owner",
    subjectType: sqlString(kind),
    subjectId: "v_id::text",
  });

  return `
-- Creates a ${kind} (${kind} null) or updates the keys attrs names.
-- Returns its row. The owner watches it when notifications is installed.
create or replace function ${names.fn(fnName)}(tenant ${ctx.idType}, ${kind} uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := ${fnName}.${kind};
  v_created boolean := ${fnName}.${kind} is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  ${guard(names.scope, `${fnName}.tenant`, names.write, "PARTY_FORBIDDEN")}
  if jsonb_typeof(coalesce(${fnName}.attrs, '{}')) <> 'object' then
    ${fail("PARTY_ATTRS_INVALID", "attrs must be an object", "22023")}
  end if;${unsupported(ctx, kind, `${fnName}.attrs`)}
  if ${has("lifecycle")} and not (${arg("lifecycle")} = any (${stages})) then
    ${fail("PARTY_LIFECYCLE_INVALID", "unknown lifecycle stage", "22023")}
  end if;
  ${ctx.hook(`before_${spec.hook}_save`, [
    [ctx.idType, `${fnName}.tenant`],
    ["uuid", `${fnName}.${kind}`],
    ["jsonb", `${fnName}.attrs`],
  ])}
  begin
    if v_created then
      if ${text(arg("name"))} is null then
        ${fail("PARTY_NAME_REQUIRED", "a name is required", "23502")}
      end if;
      insert into ${table} (${insertColumns.join(", ")})
      values (${insertValues.join(", ")})
      returning ${owner ? `${col("id")}, ${col("owner")} into v_id, v_owner` : `${col("id")} into v_id`};
    else${
      owner
        ? `
      select x.${col("owner")} into v_previous_owner from ${table} x
      where x.${col("id")} = ${fnName}.${kind} and x.${col("tenant")} = ${fnName}.tenant;`
        : ""
    }
      update ${table} x set ${updates.join(",\n        ")}
      where x.${col("id")} = ${fnName}.${kind} and x.${col("tenant")} = ${fnName}.tenant and x.${col("mergedInto")} is null
      returning x.${owner ? col("owner") : col("id")} into ${owner ? "v_owner" : "v_id"};
      if not found then
        ${fail("PARTY_NOT_FOUND", `${kind} not found`, "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail(spec.taken[0], spec.taken[1], "23505")}
  end;
  select to_jsonb(x)${extraFields(ctx, kind, "x")} into v_row from ${table} x where x.${col("id")} = v_id;
  if v_created then
    ${ctx.record({ type: `${kind}.created`, payload, subject, tenant: `${fnName}.tenant::text`, audit: false })}
  else
    ${ctx.record({ type: `${kind}.updated`, payload, subject, tenant: `${fnName}.tenant::text`, audit: false })}
  end if;${
    watch === ""
      ? ""
      : `
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    ${watch}
  end if;`
  }
  ${ctx.hook(`after_${spec.hook}_save`, [
    ["uuid", "v_id"],
    ["boolean", "v_created"],
  ])}
  return v_row;
end;
$$;
${userGrant(`${names.fn(fnName)}(${ctx.idType}, uuid, jsonb)`)}
`;
}

function archiveFunction(
  ctx: BlockSqlContext,
  names: PartyNames,
  kind: Kind,
): string {
  const spec = SPEC[kind];
  const { t, c, fn } = names;
  const col = (logical: string): string => c(spec.table, logical);
  const name = `archive_${kind}`;

  return `
-- Archives a ${kind} (archived true) or restores it.
create or replace function ${fn(name)}(id uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_name text;
begin
  select x.${col("tenant")}, x.${col("name")} into v_tenant, v_name from ${t(spec.table)} x where x.${col("id")} = ${name}.id;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names.scope, `v_tenant`, names.write, "PARTY_FORBIDDEN")}
  begin
    update ${t(spec.table)} x set ${col("archivedAt")} = case when ${name}.archived then coalesce(x.${col("archivedAt")}, now()) end, ${col("updatedAt")} = now()
    where x.${col("id")} = ${name}.id;
  exception when unique_violation then
    ${fail(spec.taken[0], spec.taken[1], "23505")}
  end;
  if ${name}.archived then
    __RECORD__
  end if;
  return true;
end;
$$;
${userGrant(`${fn(name)}(uuid, boolean)`)}
`;
}

function mergeFunction(
  ctx: BlockSqlContext,
  names: PartyNames,
  kind: Kind,
): string {
  const spec = SPEC[kind];
  const { t, c } = names;
  const col = (logical: string): string => c(spec.table, logical);
  const li = (logical: string): string => c("links", logical);
  const linkColumn = kind === "company" ? li("company") : li("person");
  const role = ctx.has("links", "role");

  return recordMergeFunction(ctx, {
    name: kind === "company" ? "merge_companies" : "merge_people",
    table: spec.table,
    guard: (tenant) =>
      guard(names.scope, tenant, names.manage, "PARTY_FORBIDDEN"),
    notFound: ["PARTY_NOT_FOUND", `${kind} not found`],
    invalid: [
      "PARTY_MERGE_INVALID",
      "merge two different, unmerged records of one organization",
    ],
    clear: [kind === "company" ? "domain" : "email"],
    fill: fieldsOf(ctx, kind)
      .filter((field) => field.key !== "name" && field.key !== "lifecycle")
      .map((field) => field.column),
    move: (
      keep,
      drop,
    ) => `insert into ${t("links")} (${li("tenant")}, ${li("company")}, ${li("person")}${role ? `, ${li("role")}` : ""}, ${li("isPrimary")})
  select l.${li("tenant")}, ${kind === "company" ? `${keep}, l.${li("person")}` : `l.${li("company")}, ${keep}`}${role ? `, l.${li("role")}` : ""}, false
  from ${t("links")} l where l.${linkColumn} = ${drop}
  on conflict do nothing;
  delete from ${t("links")} l where l.${linkColumn} = ${drop};${kind === "person" ? `${identityMergeMoves(names, keep, drop)}${personMergeMoves(ctx, keep, drop)}` : ""}`,
    record: (keep, drop) =>
      ctx.record({
        type: `${kind}.merged`,
        payload: `jsonb_build_object('organizationId', v_keep.${col("tenant")}, ${sqlString(spec.idKey)}, ${keep}, 'name', v_keep.${col("name")}, 'mergedId', ${drop})`,
        subject: `'${spec.subject}/' || ${keep}::text`,
        tenant: `v_keep.${col("tenant")}::text`,
        audit: {
          category: "data",
          targetType: kind,
          recordId: `${keep}::text`,
          targetLabel: `v_keep.${col("name")}`,
          summary: `'merged ' || v_drop.${col("name")} || ' into ' || v_keep.${col("name")}`,
        },
      }),
    returns: (keep) =>
      `(select to_jsonb(x)${extraFields(ctx, kind, "x")} from ${t(spec.table)} x where x.${col("id")} = ${keep})`,
  });
}

function listFunction(
  ctx: BlockSqlContext,
  names: PartyNames,
  kind: Kind,
): string {
  const spec = SPEC[kind];
  const { t, c, fn } = names;
  const col = (logical: string): string => c(spec.table, logical);
  const name = kind === "company" ? "list_companies" : "list_people";

  const searchable =
    kind === "company"
      ? `x.${col("name")} ilike v_like or x.${col("domain")} ilike v_like`
      : `x.${col("name")} ilike v_like or x.${col("email")} ilike v_like`;

  return `
-- A page of the organization's active ${spec.table}, by name. search matches
-- the name and ${kind === "company" ? "domain" : "email"}; after_name and after_id continue after the
-- last row of the previous page.
create or replace function ${fn(name)}(tenant ${ctx.idType}, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_like text := '%' || replace(replace(replace(coalesce(${name}.search, ''), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%';
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p)${extraFields(ctx, kind, "p")} order by lower(p.${col("name")}), p.${col("id")})
    from (
      select x.* from ${t(spec.table)} x
      where x.${col("tenant")} = ${name}.tenant
        and x.${col("archivedAt")} is null
        and (${name}.search is null or ${searchable})
        and (${name}.lifecycle is null or ${asText(ctx, spec.table, `x.${col("lifecycle")}`)} = ${name}.lifecycle)
        and (${name}.owner is null or ${ctx.has(spec.table, "owner") ? `x.${col("owner")} = ${name}.owner` : "false"})
        and (${name}.after_name is null or (lower(x.${col("name")}), x.${col("id")}) > (lower(${name}.after_name), ${name}.after_id))
      order by lower(x.${col("name")}), x.${col("id")}
      limit ${pageSize(`${name}.page_size`, 50, 200)}
    ) p
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn(name)}(${ctx.idType}, text, text, uuid, text, uuid, integer)`)}
`;
}

export function partyFunctions(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  const { t, c, fn } = names;
  const li = (logical: string): string => c("links", logical);
  const co = (logical: string): string => c("companies", logical);
  const pe = (logical: string): string => c("people", logical);
  const role = ctx.has("links", "role");

  const linkPayload = (name: string): string =>
    `jsonb_build_object('organizationId', v_tenant, 'companyId', ${name}.company, 'personId', ${name}.person, 'role', v_role)`;

  const archived = (kind: Kind): string => {
    const spec = SPEC[kind];

    return ctx.record({
      type: `${kind}.archived`,
      payload: `jsonb_build_object('organizationId', v_tenant, ${sqlString(spec.idKey)}, archive_${kind}.id, 'name', v_name)`,
      subject: `'${spec.subject}/' || archive_${kind}.id::text`,
      tenant: "v_tenant::text",
      audit: false,
    });
  };

  return `${saveFunction(ctx, names, "company")}${saveFunction(ctx, names, "person")}
${archiveFunction(ctx, names, "company").replace("__RECORD__", archived("company"))}
${archiveFunction(ctx, names, "person").replace("__RECORD__", archived("person"))}
-- Links a person to a company with a role, or changes the link. A primary
-- link replaces the company's previous primary contact.
create or replace function ${fn("set_company_person")}(company uuid, person uuid, role text, is_primary boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_role text := nullif(trim(set_company_person.role), '');
begin${
    role
      ? ""
      : `
  if v_role is not null then
    ${fail("PARTY_ROLE_UNSUPPORTED", `this ${ctx.tableName("links").name} table has no role column`, "22023")}
  end if;`
  }
  select x.${co("tenant")} into v_tenant from ${t("companies")} x
  join ${t("people")} p on p.${pe("id")} = set_company_person.person and p.${pe("tenant")} = x.${co("tenant")}
  where x.${co("id")} = set_company_person.company;
  if v_tenant is null then
    ${fail("PARTY_NOT_FOUND", "company or person not found in one organization", "P0002")}
  end if;
  ${guard(names.scope, "v_tenant", names.write, "PARTY_FORBIDDEN")}
  if coalesce(set_company_person.is_primary, false) then
    update ${t("links")} l set ${li("isPrimary")} = false
    where l.${li("company")} = set_company_person.company and l.${li("person")} <> set_company_person.person and l.${li("isPrimary")};
  end if;
  insert into ${t("links")} (${li("tenant")}, ${li("company")}, ${li("person")}${role ? `, ${li("role")}` : ""}, ${li("isPrimary")})
  select x.${co("tenant")}, set_company_person.company, set_company_person.person${role ? ", v_role" : ""}, coalesce(set_company_person.is_primary, false)
  from ${t("companies")} x where x.${co("id")} = set_company_person.company
  on conflict (${li("company")}, ${li("person")}) do update set ${role ? `${li("role")} = excluded.${li("role")}, ` : ""}${li("isPrimary")} = excluded.${li("isPrimary")};
  ${ctx.record({
    type: "company.person_linked",
    payload: linkPayload("set_company_person"),
    subject: "'companies/' || set_company_person.company::text",
    tenant: "v_tenant::text",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("set_company_person")}(uuid, uuid, text, boolean)`)}

create or replace function ${fn("remove_company_person")}(company uuid, person uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_role text;
begin
  select l.${li("tenant")}, ${role ? `l.${li("role")}` : "null"} into v_tenant, v_role from ${t("links")} l
  where l.${li("company")} = remove_company_person.company and l.${li("person")} = remove_company_person.person;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names.scope, "v_tenant", names.write, "PARTY_FORBIDDEN")}
  delete from ${t("links")} l where l.${li("company")} = remove_company_person.company and l.${li("person")} = remove_company_person.person;
  ${ctx.record({
    type: "company.person_unlinked",
    payload: linkPayload("remove_company_person"),
    subject: "'companies/' || remove_company_person.company::text",
    tenant: "v_tenant::text",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("remove_company_person")}(uuid, uuid)`)}
${mergeFunction(ctx, names, "company")}${mergeFunction(ctx, names, "person")}${listFunction(ctx, names, "company")}${listFunction(ctx, names, "person")}
-- The people of a company with their role, primary contact first.
create or replace function ${fn("company_people_of")}(company uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('role', ${role ? `l.${li("role")}` : "null"}, 'is_primary', l.${li("isPrimary")})
    order by l.${li("isPrimary")} desc, lower(p.${pe("name")}), p.${pe("id")}), '[]'::jsonb)
  from ${t("links")} l join ${t("people")} p on p.${pe("id")} = l.${li("person")}
  where l.${li("company")} = company_people_of.company and p.${pe("archivedAt")} is null
$$;
${userGrant(`${fn("company_people_of")}(uuid)`)}`;
}
