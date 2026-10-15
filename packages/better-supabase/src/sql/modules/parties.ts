import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  lockTable,
  schemaPreamble,
  tenantIn,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import { partyFunctions, type PartyNames } from "./parties-functions.ts";
import { partiesInboxSql } from "./parties-inbox.ts";

/** The lifecycle stages `options.companyLifecycles` falls back to. */
const COMPANY_LIFECYCLES = ["lead", "prospect", "customer", "churned"] as const;

/** The lifecycle stages `options.personLifecycles` falls back to. */
const PERSON_LIFECYCLES = [
  "lead",
  "mql",
  "sql",
  "opportunity",
  "customer",
] as const;

const COMPANY = ["organizationId", "companyId", "name"] as const;
const PERSON = ["organizationId", "personId", "name"] as const;
const LINK = ["organizationId", "companyId", "personId", "role"] as const;

const EVENTS: ModuleEvents = {
  "company.created": { subject: "companies", payload: [...COMPANY] },
  "company.updated": { subject: "companies", payload: [...COMPANY] },
  "company.archived": { subject: "companies", payload: [...COMPANY] },
  "company.merged": {
    subject: "companies",
    payload: [...COMPANY, "mergedId"],
  },
  "company.person_linked": { subject: "companies", payload: [...LINK] },
  "company.person_unlinked": { subject: "companies", payload: [...LINK] },
  "person.created": { subject: "persons", payload: [...PERSON] },
  "person.updated": { subject: "persons", payload: [...PERSON] },
  "person.archived": { subject: "persons", payload: [...PERSON] },
  "person.merged": { subject: "persons", payload: [...PERSON, "mergedId"] },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_company_save",
    "after_company_save",
    "before_person_save",
    "after_person_save",
  ],
  options: ["companyLifecycles", "personLifecycles", "extraColumns"],
  tables: {
    companies: {
      name: "companies",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        domain: "domain",
        website: "website",
        vatId: "vat_id",
        lifecycle: "lifecycle",
        owner: "owner_user_id",
        address: "address",
        mergedInto: "merged_into",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    people: {
      name: "people",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        email: "email",
        phone: "phone",
        title: "title",
        lifecycle: "lifecycle",
        owner: "owner_user_id",
        user: "user_id",
        mergedInto: "merged_into",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    links: {
      name: "company_people",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        company: "company_id",
        person: "person_id",
        role: "role",
        isPrimary: "is_primary",
        createdAt: "created_at",
      },
    },
    personContacts: {
      name: "person_inbox_contacts",
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        person: "person_id",
        contact: "contact_id",
        createdAt: "created_at",
      },
    },
  },
};

const STAGE = /^[a-z][a-z0-9_]{0,62}$/;

function lifecycles(
  ctx: ModuleContext,
  name: "companyLifecycles" | "personLifecycles",
  fallback: readonly string[],
): readonly string[] {
  const list = ctx.list(name, fallback);
  if (list.length === 0 || list.some((item) => !STAGE.test(item))) {
    throw new TypeError(
      `blocks.parties.options.${name} must be a non-empty list of lowercase names`,
    );
  }
  return list;
}

const textArray = (items: readonly string[]): string =>
  `${sqlString(`{${items.join(",")}}`)}::text[]`;

function tables(ctx: ModuleContext, names: PartyNames): string {
  if (!ctx.manages) return "";
  const { t, c } = names;
  const read = (
    table: string,
  ): string => `drop policy if exists ${ctx.tableName(table).name}_read on ${t(table)};
create policy ${ctx.tableName(table).name}_read on ${t(table)} for select to authenticated
using (${tenantIn(c(table, "tenant"), names.read)});`;
  const co = (column: string): string => c("companies", column);
  const pe = (column: string): string => c("people", column);
  const li = (column: string): string => c("links", column);
  return `
create table if not exists ${t("companies")} (
  ${co("id")} uuid primary key default gen_random_uuid(),
  ${co("tenant")} ${ctx.idType} not null,
  ${co("name")} text not null check (length(${co("name")}) between 1 and 300),
  ${co("domain")} text check (${co("domain")} = lower(${co("domain")}) and ${co("domain")} ~ '^[a-z0-9.-]+\\.[a-z]{2,}$'),
  ${co("website")} text,
  ${co("vatId")} text,
  ${co("lifecycle")} text not null,
  ${co("owner")} uuid,
  ${co("address")} jsonb check (${co("address")} is null or jsonb_typeof(${co("address")}) = 'object'),
  ${co("mergedInto")} uuid references ${t("companies")} (${co("id")}),
  ${co("archivedAt")} timestamptz,
  ${co("createdBy")} uuid,
  ${co("createdAt")} timestamptz not null default now(),
  ${co("updatedAt")} timestamptz not null default now()
);
create index if not exists companies_tenant_name_idx on ${t("companies")} (${co("tenant")}, lower(${co("name")}), ${co("id")});
create unique index if not exists companies_domain_idx on ${t("companies")} (${co("tenant")}, ${co("domain")})
  where ${co("domain")} is not null and ${co("archivedAt")} is null;
create index if not exists companies_owner_idx on ${t("companies")} (${co("owner")});
create index if not exists companies_merged_into_idx on ${t("companies")} (${co("mergedInto")});${addExtraColumns(t("companies"), ctx.extraColumns("companies"))}
${lockTable(t("companies"), { read: true })}
${read("companies")}

create table if not exists ${t("people")} (
  ${pe("id")} uuid primary key default gen_random_uuid(),
  ${pe("tenant")} ${ctx.idType} not null,
  ${pe("name")} text not null check (length(${pe("name")}) between 1 and 300),
  ${pe("email")} text check (${pe("email")} = lower(${pe("email")}) and ${pe("email")} ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  ${pe("phone")} text,
  ${pe("title")} text,
  ${pe("lifecycle")} text not null,
  ${pe("owner")} uuid,
  ${pe("user")} uuid,
  ${pe("mergedInto")} uuid references ${t("people")} (${pe("id")}),
  ${pe("archivedAt")} timestamptz,
  ${pe("createdBy")} uuid,
  ${pe("createdAt")} timestamptz not null default now(),
  ${pe("updatedAt")} timestamptz not null default now()
);
create index if not exists people_tenant_name_idx on ${t("people")} (${pe("tenant")}, lower(${pe("name")}), ${pe("id")});
create unique index if not exists people_email_idx on ${t("people")} (${pe("tenant")}, ${pe("email")})
  where ${pe("email")} is not null and ${pe("archivedAt")} is null;
create index if not exists people_owner_idx on ${t("people")} (${pe("owner")});
create index if not exists people_user_idx on ${t("people")} (${pe("user")});
create index if not exists people_merged_into_idx on ${t("people")} (${pe("mergedInto")});
${lockTable(t("people"), { read: true })}
${read("people")}

create table if not exists ${t("links")} (
  ${li("tenant")} ${ctx.idType} not null,
  ${li("company")} uuid not null references ${t("companies")} (${co("id")}) on delete cascade,
  ${li("person")} uuid not null references ${t("people")} (${pe("id")}) on delete cascade,
  ${li("role")} text,
  ${li("isPrimary")} boolean not null default false,
  ${li("createdAt")} timestamptz not null default now(),
  primary key (${li("company")}, ${li("person")})
);
create index if not exists company_people_person_idx on ${t("links")} (${li("person")});
create unique index if not exists company_people_primary_idx on ${t("links")} (${li("company")}) where ${li("isPrimary")};
${lockTable(t("links"), { read: true })}
${read("links")}
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const keys = moduleOperations("parties");
  const names: PartyNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    manage: ctx.permission("manage", keys.manage),
    companyStages: textArray(
      lifecycles(ctx, "companyLifecycles", COMPANY_LIFECYCLES),
    ),
    personStages: textArray(
      lifecycles(ctx, "personLifecycles", PERSON_LIFECYCLES),
    ),
  };
  return `${schemaPreamble(ctx)}
-- Companies and people an organization works with, and who works where.
${tables(ctx, names)}${partyFunctions(ctx, names)}${partiesInboxSql(ctx, names)}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    { name: "save_company", args: ["{id}", "uuid", "jsonb"], returns: "jsonb" },
    { name: "save_person", args: ["{id}", "uuid", "jsonb"], returns: "jsonb" },
    {
      name: "set_company_person",
      args: ["uuid", "uuid", "text", "boolean"],
      returns: "boolean",
    },
    {
      name: "remove_company_person",
      args: ["uuid", "uuid"],
      returns: "boolean",
    },
    {
      name: "archive_company",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "archive_person", args: ["uuid", "boolean"], returns: "boolean" },
    { name: "merge_companies", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "merge_people", args: ["uuid", "uuid"], returns: "jsonb" },
    {
      name: "list_companies",
      args: ["{id}", "text", "text", "uuid", "text", "uuid", "integer"],
      returns: "jsonb",
    },
    {
      name: "list_people",
      args: ["{id}", "text", "text", "uuid", "text", "uuid", "integer"],
      returns: "jsonb",
    },
    { name: "company_people_of", args: ["uuid"], returns: "jsonb" },
    ...(ctx.installed("inbox")
      ? [
          {
            name: "link_inbox_contact",
            args: ["uuid", "uuid"],
            returns: "boolean",
          },
          { name: "unlink_inbox_contact", args: ["uuid"], returns: "boolean" },
          {
            name: "person_for_inbox_contact",
            args: ["uuid", "boolean"],
            returns: "jsonb",
          },
        ]
      : []),
  ];
}

export const PARTIES: ModuleDefinition = {
  name: "parties",
  title: "Parties",
  description:
    "Companies and people an organization works with: lifecycle stages, owners, who works where with a role and a primary contact, domain and email dedupe, merges and keyset-paged search.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit", "notifications", "inbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
