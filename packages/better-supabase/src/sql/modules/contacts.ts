import type { ContactsEvents } from "../../blocks/contacts/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { PartyNames } from "./contacts-functions.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, schemaPreamble } from "../shared.ts";
import { partyFunctions, partyJson } from "./contacts-functions.ts";
import {
  identitiesTable,
  identityFunctions,
  peopleInboxColumns,
} from "./contacts-identities.ts";
import { personReferences } from "./contacts-inbox.ts";
import {
  representativeFunctions,
  representsKind,
} from "./contacts-representatives.ts";
import {
  PARTY_ROLES,
  ROLE_COLUMNS,
  ROLE_OPTIONAL,
  ratesSuppliers,
  roleColumns,
  roleFunctions,
  roleIndexes,
} from "./contacts-roles.ts";
import {
  deliveryTable,
  termsFunctions,
  termsImportTargets,
  termsTable,
} from "./contacts-terms.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

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
const SUPPLIER_STATUS = ["status", "previousStatus", "reason"] as const;

const EVENTS: BlockSqlEvents<ContactsEvents> = {
  "company.created": { subject: "companies", payload: [...COMPANY] },
  "company.updated": { subject: "companies", payload: [...COMPANY] },
  "company.archived": { subject: "companies", payload: [...COMPANY] },
  "company.merged": { subject: "companies", payload: [...COMPANY, "mergedId"] },
  "company.person_linked": { subject: "companies", payload: [...LINK] },
  "company.person_unlinked": { subject: "companies", payload: [...LINK] },
  "person.created": { subject: "persons", payload: [...PERSON] },
  "person.updated": { subject: "persons", payload: [...PERSON] },
  "person.archived": { subject: "persons", payload: [...PERSON] },
  "person.merged": { subject: "persons", payload: [...PERSON, "mergedId"] },
  "company.supplier_status_changed": {
    subject: "companies",
    payload: [...COMPANY, ...SUPPLIER_STATUS],
  },
  "person.supplier_status_changed": {
    subject: "persons",
    payload: [...PERSON, ...SUPPLIER_STATUS],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    company: {
      table: "companies",
      singular: "company",
      plural: "companies",
      subject: {
        title: "name",
        permissions: { read: "read", write: "write" },
        search: { title: "name", body: ["domain"] },
      },
    },
    person: {
      table: "people",
      singular: "person",
      plural: "people",
      subject: {
        title: "name",
        permissions: { read: "read", write: "write" },
        search: { title: "name", body: ["email", "title"] },
      },
    },
  },
  events: EVENTS,
  hooks: [
    "before_company_save",
    "after_company_save",
    "before_person_save",
    "after_person_save",
  ],
  options: ["companyLifecycles", "personLifecycles", "roles", "extraColumns"],
  tables: {
    companies: {
      name: "companies",
      app: {},
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
        ...ROLE_COLUMNS,
        mergedInto: "merged_into",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["vatId", "owner", "address", "createdBy", ...ROLE_OPTIONAL],
      typed: ["lifecycle"],
    },
    people: {
      name: "people",
      app: {},
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
        avatarUrl: "avatar_url",
        metadata: "metadata",
        ...ROLE_COLUMNS,
        mergedInto: "merged_into",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["avatarUrl", "metadata", "createdBy", ...ROLE_OPTIONAL],
      typed: ["lifecycle"],
    },
    links: {
      name: "company_people",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        company: "company_id",
        person: "person_id",
        role: "role",
        isPrimary: "is_primary",
        createdAt: "created_at",
      },
      optional: ["role"],
    },
    terms: {
      name: "payment_terms",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code",
        name: "name",
        days: "days",
        discountBps: "discount_bps",
        discountDays: "discount_days",
        creditRestrictionBps: "credit_restriction_bps",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    deliveryPreferences: {
      name: "document_delivery_preferences",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        party: "party_id",
        documentType: "document_type",
        channel: "channel",
        copies: "copies",
        email: "email",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    identities: {
      name: "person_identities",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        person: "person_id",
        channel: "channel",
        address: "address",
        verifiedAt: "verified_at",
        createdAt: "created_at",
      },
      optional: ["verifiedAt", "createdAt"],
    },
  },
};

const STAGE = /^[a-z][a-z0-9_]{0,62}$/;

function lifecycles(
  ctx: BlockSqlContext,
  name: "companyLifecycles" | "personLifecycles",
  fallback: readonly string[],
): readonly string[] {
  const list = ctx.list(name, fallback);

  if (list.length === 0 || list.some((item) => !STAGE.test(item))) {
    throw new TypeError(
      `blocks.contacts.options.${name} must be a non-empty list of lowercase names`,
    );
  }

  return list;
}

/** `options.roles`: the roles a company or person can have. */
function partyRoles(ctx: BlockSqlContext): readonly string[] {
  const list = ctx.list("roles", PARTY_ROLES);

  if (list.length === 0 || list.some((item) => !STAGE.test(item))) {
    throw new TypeError(
      "blocks.contacts.options.roles must be a non-empty list of lowercase names",
    );
  }

  return list;
}

/** A new person's lifecycle stage: the first configured one. */
export function personStage(ctx: BlockSqlContext): string {
  const [first = "lead"] = lifecycles(
    ctx,
    "personLifecycles",
    PERSON_LIFECYCLES,
  );

  return first;
}

const textArray = (items: readonly string[]): string =>
  `${sqlString(`{${items.join(",")}}`)}::text[]`;

function tables(ctx: BlockSqlContext, names: PartyNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = names;

  const read = (table: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(c(table, "tenant"), names.read),
      }),
      { drop: true, target: t(table) },
    );

  const co = (column: string): string => c("companies", column);
  const pe = (column: string): string => c("people", column);
  const li = (column: string): string => c("links", column);

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical) ? `\n  ${definition(c(table, logical))},` : "";

  return `${termsTable(ctx, names)}
create table if not exists ${t("companies")} (
  ${co("id")} uuid primary key default gen_random_uuid(),
  ${co("tenant")} ${ctx.idType} not null,
  ${co("name")} text not null check (length(${co("name")}) between 1 and 300),
  ${co("domain")} text check (${co("domain")} = lower(${co("domain")}) and ${co("domain")} ~ '^[a-z0-9.-]+\\.[a-z]{2,}$'),
  ${co("website")} text,${column("companies", "vatId", (name) => `${name} text`)}
  ${co("lifecycle")} text not null,${column("companies", "owner", (name) => `${name} uuid`)}${column("companies", "address", (name) => `${name} jsonb check (${name} is null or jsonb_typeof(${name}) = 'object')`)}${roleColumns(ctx, "companies")}
  ${co("mergedInto")} uuid references ${t("companies")} (${co("id")}),
  ${co("archivedAt")} timestamptz,${column("companies", "createdBy", (name) => `${name} uuid`)}
  ${co("createdAt")} timestamptz not null default now(),
  ${co("updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("companies_tenant_name_idx")} on ${t("companies")} (${co("tenant")}, lower(${co("name")}), ${co("id")});
create unique index if not exists ${ctx.naming.rename("companies_domain_idx")} on ${t("companies")} (${co("tenant")}, ${co("domain")})
  where ${co("domain")} is not null and ${co("archivedAt")} is null;${ctx.has("companies", "owner") ? `\ncreate index if not exists ${ctx.naming.rename("companies_owner_idx")} on ${t("companies")} (${co("owner")});` : ""}
create index if not exists ${ctx.naming.rename("companies_merged_into_idx")} on ${t("companies")} (${co("mergedInto")});${roleIndexes(ctx, "companies")}${addExtraColumns(t("companies"), ctx.extraColumns("companies"))}
${lockModuleTable(ctx, "companies", { read: true })}
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
  ${pe("user")} uuid,${column("people", "avatarUrl", (name) => `${name} text`)}${column("people", "metadata", (name) => `${name} jsonb not null default '{}'::jsonb check (jsonb_typeof(${name}) = 'object')`)}${roleColumns(ctx, "people")}
  ${pe("mergedInto")} uuid references ${t("people")} (${pe("id")}),
  ${pe("archivedAt")} timestamptz,${column("people", "createdBy", (name) => `${name} uuid`)}
  ${pe("createdAt")} timestamptz not null default now(),
  ${pe("updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("people_tenant_name_idx")} on ${t("people")} (${pe("tenant")}, lower(${pe("name")}), ${pe("id")});
create unique index if not exists ${ctx.naming.rename("people_email_idx")} on ${t("people")} (${pe("tenant")}, ${pe("email")})
  where ${pe("email")} is not null and ${pe("archivedAt")} is null;
create index if not exists ${ctx.naming.rename("people_owner_idx")} on ${t("people")} (${pe("owner")});
create index if not exists ${ctx.naming.rename("people_user_idx")} on ${t("people")} (${pe("user")});
create index if not exists ${ctx.naming.rename("people_merged_into_idx")} on ${t("people")} (${pe("mergedInto")});${roleIndexes(ctx, "people")}
${lockModuleTable(ctx, "people", { read: true })}
${read("people")}

create table if not exists ${t("links")} (
  ${li("tenant")} ${ctx.idType} not null,
  ${li("company")} uuid not null references ${t("companies")} (${co("id")}) on delete cascade,
  ${li("person")} uuid not null references ${t("people")} (${pe("id")}) on delete cascade,${column("links", "role", (name) => `${name} text`)}
  ${li("isPrimary")} boolean not null default false,
  ${li("createdAt")} timestamptz not null default now(),
  primary key (${li("company")}, ${li("person")})
);${appUniqueIndex(ctx, "links", ["company", "person"])}
create index if not exists ${ctx.naming.rename("company_people_person_idx")} on ${t("links")} (${li("person")});
create unique index if not exists ${ctx.naming.rename("company_people_primary_idx")} on ${t("links")} (${li("company")}) where ${li("isPrimary")};
${lockModuleTable(ctx, "links", { read: true })}
${read("links")}
`;
}

function partyNames(ctx: BlockSqlContext): PartyNames {
  const keys = moduleOperations("contacts");

  return {
    scope: ctx.scope,
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
    roles: textArray(partyRoles(ctx)),
    approveSupplier: ctx.permission("approveSupplier", keys.approveSupplier),
  };
}

/**
 * The people and identity tables as an upgrade of another block creates them
 * before the module file runs: the inbox moves its contacts onto them.
 */
export function contactsUpgradeTables(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const names = partyNames(ctx);

  return `${schemaPreamble(ctx)}
${tables(ctx, names)}${deliveryTable(ctx, names)}${peopleInboxColumns(ctx)}
${identitiesTable(ctx, names)}`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const names = partyNames(ctx);

  return `${schemaPreamble(ctx)}
-- Companies and people an organization works with, and who works where.
${tables(ctx, names)}${deliveryTable(ctx, names)}${identitiesTable(ctx, names)}${partyFunctions(ctx, names)}${termsFunctions(ctx, names)}${roleFunctions(ctx, names, (kind, alias) => partyJson(ctx, kind, alias))}${identityFunctions(ctx, names)}${personReferences(ctx, names)}${representativeFunctions(ctx, names)}`;
}

const CONTRIBUTES: BlockContributes = {
  relations: (own) => [representsKind(own)],
  imports: termsImportTargets,
};

const LIST_ARGS = [
  "{id}",
  "text",
  "text",
  "uuid",
  "text",
  "uuid",
  "integer",
  "text",
  "text",
];

/** Whether companies or people have the role column `logical`. */
const hasRole = (ctx: BlockSqlContext, logical: string): boolean =>
  ctx.has("companies", logical) || ctx.has("people", logical);

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
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
    { name: "archive_company", args: ["uuid", "boolean"], returns: "boolean" },
    { name: "archive_person", args: ["uuid", "boolean"], returns: "boolean" },
    { name: "merge_companies", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "merge_people", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "list_companies", args: LIST_ARGS, returns: "jsonb" },
    { name: "list_people", args: LIST_ARGS, returns: "jsonb" },
    { name: "company_people_of", args: ["uuid"], returns: "jsonb" },
    { name: "list_person_identities", args: ["uuid"], returns: "jsonb" },
    { name: "save_payment_term", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_payment_terms", args: ["{id}"], returns: "jsonb" },
    { name: "delete_payment_term", args: ["uuid"], returns: "boolean" },
    {
      name: "set_document_delivery_preferences",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "list_document_delivery_preferences",
      args: ["uuid"],
      returns: "jsonb",
    },
    {
      name: "add_person_identity",
      args: ["uuid", "text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "remove_person_identity", args: ["uuid"], returns: "boolean" },
    {
      name: "find_person_by_identity",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    ...(hasRole(ctx, "roles")
      ? [
          {
            name: "set_party_roles",
            args: ["uuid", "text[]"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(hasRole(ctx, "supplierStatus")
      ? [
          {
            name: "set_supplier_status",
            args: ["uuid", "text", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(ratesSuppliers(ctx)
      ? [
          {
            name: "supplier_status_from_qualifications",
            args: ["uuid"],
            returns: "text",
          },
        ]
      : []),
    ...(ctx.installed("relations")
      ? [
          {
            name: "list_representatives",
            args: ["text", "text"],
            returns: "jsonb",
          },
          { name: "represented_by_me", args: ["{id}"], returns: "jsonb" },
        ]
      : []),
  ];
}

export const PARTIES: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "contacts",
  scopes: ["tenant"],
  title: "Parties",
  description:
    "Companies and people an organization works with: lifecycle stages, owners, party roles (customer, supplier and so on), payment terms with early-payment discounts and credit restrictions, credit limits with a soft or hard block, a language, delivery preferences per document type and a supplier status, who works where with a role and a primary contact, each person's addresses on channels (the inbox's contacts), domain and email dedupe, merges and keyset-paged search.",
  requires: ["memberships", "permissions"],
  integrates: [
    "outbox",
    "audit",
    "notifications",
    "inbox",
    "identities",
    "relations",
    "qualifications",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  internal: [
    "resolve_person",
    "payment_term_write",
    "delivery_preference_write",
    "resolve_payment_terms",
  ],
  names: NAMES,
  contract,
  build,
};
