import type { DocumentTemplatesEvents } from "../../blocks/document-templates/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble, triggerGrant } from "../shared.ts";
import { documentTemplateFunctions } from "./document-templates-functions.ts";
import {
  documentTemplateImportFunctions,
  documentTemplateImportTargets,
} from "./document-templates-import.ts";
import {
  DOCUMENT_BODY_MAX,
  DOCUMENT_LANGUAGE_PATTERN,
  DOCUMENT_TEXT_KEY_PATTERN,
  DOCUMENT_TYPES,
} from "./document-templates-values.ts";
import { documentVariableFunctions } from "./document-templates-variables.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<DocumentTemplatesEvents> = {
  "document_template.created": {
    subject: "document-templates",
    payload: [
      "organizationId",
      "templateId",
      "documentType",
      "legalEntityId",
      "language",
      "name",
      "version",
    ],
  },
  "document_template.updated": {
    subject: "document-templates",
    payload: [
      "organizationId",
      "templateId",
      "documentType",
      "legalEntityId",
      "language",
      "name",
      "version",
    ],
  },
  "document_text_block.created": {
    subject: "document-templates",
    payload: [
      "organizationId",
      "textBlockId",
      "key",
      "legalEntityId",
      "language",
      "version",
    ],
  },
  "document_text_block.updated": {
    subject: "document-templates",
    payload: [
      "organizationId",
      "textBlockId",
      "key",
      "legalEntityId",
      "language",
      "version",
    ],
  },
  "document_snapshot.created": {
    subject: "document-templates",
    payload: [
      "organizationId",
      "snapshotId",
      "documentType",
      "documentId",
      "templateVersion",
    ],
  },
};

const NAME_PATTERN = "^[a-z][a-z0-9_-]{0,63}$";

const NAMES: BlockSqlNames = {
  entities: {
    document_template: {
      table: "templates",
      singular: "document_template",
      primary: true,
    },
    document_text_block: {
      table: "textBlocks",
      singular: "document_text_block",
    },
    document_snapshot: { table: "snapshots", singular: "document_snapshot" },
  },
  events: EVENTS,
  hooks: [
    "before_document_template_save",
    "after_document_template_save",
    "before_document_text_block_save",
    "after_document_text_block_save",
  ],
  tables: {
    templates: {
      name: "document_templates",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        legalEntity: "legal_entity_id",
        documentType: "document_type",
        language: "language",
        name: "name",
        body: "body",
        version: "version",
        active: "active",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    textBlocks: {
      name: "document_text_blocks",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        legalEntity: "legal_entity_id",
        key: "key",
        language: "language",
        body: "body",
        version: "version",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    snapshots: {
      name: "rendered_documents",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        documentType: "document_type",
        documentId: "document_id",
        language: "language",
        legalEntity: "legal_entity_id",
        contractVersion: "contract_version",
        templateId: "template_id",
        templateVersion: "template_version",
        template: "template",
        blocks: "blocks",
        variables: "variables",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const templates = ctx.table("templates");
  const blocks = ctx.table("textBlocks");
  const snapshots = ctx.table("snapshots");
  const x = (column: string): string => ctx.col("templates", column);
  const y = (column: string): string => ctx.col("textBlocks", column);
  const z = (column: string): string => ctx.col("snapshots", column);
  const legal = ctx.of("legal-entities");
  const entities = legal.table("entities");
  const e = (column: string): string => legal.col("entities", column);
  const permissions = moduleOperations("document-templates");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const types = DOCUMENT_TYPES.map((type) => `'${type}'`).join(", ");
  const zero = "'00000000-0000-0000-0000-000000000000'::uuid";

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const readPolicy = (logical: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const fn = (logical: string): string => ctx.fn(logical);

  return `
-- The templates of an organization, per document type, name, legal entity
-- (null for the organization) and language (null for any).
create table if not exists ${templates} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("legalEntity")} uuid,
  ${x("documentType")} text not null check (${x("documentType")} in (${types})),
  ${x("language")} text check (${x("language")} is null or ${x("language")} ~ '${DOCUMENT_LANGUAGE_PATTERN}'),
  ${x("name")} text not null default 'default' check (${x("name")} ~ '${NAME_PATTERN}'),
  ${x("body")} text not null check (length(btrim(${x("body")})) > 0 and length(${x("body")}) <= ${String(DOCUMENT_BODY_MAX)}),
  ${x("version")} integer not null default 1 check (${x("version")} >= 1),
  ${x("active")} boolean not null default true,
  ${x("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${x("createdAt")} timestamptz not null default now(),
  ${x("updatedAt")} timestamptz not null default now(),
  foreign key (${x("tenant")}, ${x("legalEntity")}) references ${entities} (${e("tenant")}, ${e("id")}) on delete restrict
);
${
  ctx.owns("templates")
    ? `-- One template per slot.
create unique index if not exists ${name("templates", "slot_idx")} on ${templates} (${x("tenant")}, ${x("documentType")}, ${x("name")}, coalesce(${x("legalEntity")}, ${zero}), coalesce(${x("language")}, ''));
`
    : ""
}create index if not exists ${name("templates", "lookup_idx")} on ${templates} (${x("tenant")}, ${x("documentType")}, ${x("name")}) where ${x("active")};
create index if not exists ${name("templates", "entity_idx")} on ${templates} (${x("tenant")}, ${x("legalEntity")}) where ${x("legalEntity")} is not null;
create index if not exists ${name("templates", "created_by_idx")} on ${templates} (${x("createdBy")}) where ${x("createdBy")} is not null;
${lockTable(templates, { read: true })}
${readPolicy("templates", ctx.scope.check(x("tenant"), read))}

-- Reusable texts, read in a template as texts.<key>.
create table if not exists ${blocks} (
  ${y("id")} uuid primary key default gen_random_uuid(),
  ${y("tenant")} ${ctx.idType} not null,
  ${y("legalEntity")} uuid,
  ${y("key")} text not null check (${y("key")} ~ '${DOCUMENT_TEXT_KEY_PATTERN}'),
  ${y("language")} text check (${y("language")} is null or ${y("language")} ~ '${DOCUMENT_LANGUAGE_PATTERN}'),
  ${y("body")} text not null check (length(btrim(${y("body")})) > 0 and length(${y("body")}) <= ${String(DOCUMENT_BODY_MAX)}),
  ${y("version")} integer not null default 1 check (${y("version")} >= 1),
  ${y("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${y("createdAt")} timestamptz not null default now(),
  ${y("updatedAt")} timestamptz not null default now(),
  foreign key (${y("tenant")}, ${y("legalEntity")}) references ${entities} (${e("tenant")}, ${e("id")}) on delete restrict
);
${
  ctx.owns("textBlocks")
    ? `create unique index if not exists ${name("textBlocks", "slot_idx")} on ${blocks} (${y("tenant")}, ${y("key")}, coalesce(${y("legalEntity")}, ${zero}), coalesce(${y("language")}, ''));
`
    : ""
}create index if not exists ${name("textBlocks", "entity_idx")} on ${blocks} (${y("tenant")}, ${y("legalEntity")}) where ${y("legalEntity")} is not null;
create index if not exists ${name("textBlocks", "created_by_idx")} on ${blocks} (${y("createdBy")}) where ${y("createdBy")} is not null;
${lockTable(blocks, { read: true })}
${readPolicy("textBlocks", ctx.scope.check(y("tenant"), read))}

-- What a document looked like when it was frozen: its variables, the template
-- and the text blocks it used. A snapshot never changes. The template column
-- keeps the body, so deleting or editing the template leaves it as it was.
create table if not exists ${snapshots} (
  ${z("id")} uuid primary key default gen_random_uuid(),
  ${z("tenant")} ${ctx.idType} not null,
  ${z("documentType")} text not null check (${z("documentType")} in (${types})),
  ${z("documentId")} uuid not null,
  ${z("language")} text,
  ${z("legalEntity")} uuid,
  ${z("contractVersion")} integer not null,
  ${z("templateId")} uuid,
  ${z("templateVersion")} integer,
  ${z("template")} jsonb,
  ${z("blocks")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${z("blocks")}) = 'object'),
  ${z("variables")} jsonb not null check (jsonb_typeof(${z("variables")}) = 'object'),
  ${z("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${z("createdAt")} timestamptz not null default now(),
  unique (${z("tenant")}, ${z("documentType")}, ${z("documentId")})
);
create index if not exists ${name("snapshots", "created_by_idx")} on ${snapshots} (${z("createdBy")}) where ${z("createdBy")} is not null;
${lockTable(snapshots, { read: true })}
-- A snapshot shows to someone who can read the document it froze; a statement
-- has no row of its own, so it shows to the template managers.
${readPolicy(
  "snapshots",
  `${ctx.scope.check(z("tenant"), read)} and (case when ${z("documentType")} = 'statement' then ${ctx.scope.check(z("tenant"), manage)} else ${fn("document_visible")}(${z("tenant")}, ${z("documentType")}, ${z("documentId")}) end)`,
)}
`;
}

/**
 * An issued invoice or credit note is frozen when its transaction commits: the
 * numbers, tax lines and totals are written by then. A failed freeze is a
 * warning, not a failed issue, so a template problem never blocks billing.
 * Import mode does not freeze; the history keeps rendering from live data.
 */
function freezeTrigger(ctx: BlockSqlContext): string {
  if (!ctx.installed("invoices") || ctx.of("invoices").mode === "custom") {
    return "";
  }

  const inv = ctx.of("invoices");
  const t = inv.table("invoices");
  const i = (column: string): string => inv.col("invoices", column);

  const draft = inv.is("invoices", "status", `old.${i("status")}`, ["draft"]);

  const issued = inv.is(
    "invoices",
    "status",
    `new.${i("status")}`,
    ["draft", "void"],
    true,
  );

  const credit = inv.is("invoices", "kind", `new.${i("kind")}`, [
    "credit_note",
  ]);

  return `
create or replace function ${ctx.fn("freeze_issued_invoice")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if ${ctx.importing()} then
    return null;
  end if;
  begin
    perform ${ctx.fn("document_freeze")}(new.${i("tenant")}, case when ${credit} then 'credit_note' else 'invoice' end, new.${i("id")}, null, null);
  exception when others then
    raise warning 'the document snapshot of invoice % was skipped: %', new.${i("id")}, sqlerrm;
  end;
  return null;
end;
$$;
${triggerGrant(`${ctx.fn("freeze_issued_invoice")}()`)}
drop trigger if exists bsb_document_freeze on ${t};
create constraint trigger bsb_document_freeze
  after update of ${i("status")} on ${t}
  deferrable initially deferred
  for each row
  when (${draft} and ${issued})
  execute function ${ctx.fn("freeze_issued_invoice")}();
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Document templates (ADR 0145): per legal entity and language templates, text
-- blocks, one variable contract per document type, render_document and the
-- snapshots that keep an issued document stable.
${documentVariableFunctions(ctx)}
${tables(ctx)}
${documentTemplateFunctions(ctx)}
${documentTemplateImportFunctions(ctx)}
${freezeTrigger(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "document_template_contract", args: ["text"], returns: "jsonb" },
    {
      name: "validate_document_template",
      args: ["text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "save_document_template",
      args: ["{id}", "text", "text", "text", "text", "uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "set_document_template_active",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "get_document_template", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_document_templates",
      args: ["{id}", "text", "uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "save_document_text_block",
      args: ["{id}", "text", "text", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_document_text_blocks",
      args: ["{id}", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "resolve_document_template",
      args: ["{id}", "text", "uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "resolve_document_blocks",
      args: ["{id}", "text[]", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "render_document",
      args: ["{id}", "text", "uuid", "text", "boolean", "text"],
      returns: "jsonb",
    },
    {
      name: "freeze_document",
      args: ["{id}", "text", "uuid", "text", "text"],
      returns: "jsonb",
    },
  ];
}

export const DOCUMENT_TEMPLATES: BlockSqlDefinition = {
  name: "document-templates",
  scopes: ["tenant"],
  title: "Document templates",
  description:
    "Templates for invoices, credit notes, quotes, orders, dunning letters, delivery notes and statements per legal entity and language, reusable text blocks, one versioned variable contract per document type, and render_document, which returns the variables, the chosen template and its texts. An issued invoice or credit note is frozen with the template version it used, so rendering it again never changes it.",
  requires: ["memberships", "permissions", "legal-entities"],
  integrates: [
    "invoices",
    "quotes",
    "orders",
    "shipments",
    "contacts",
    "tax",
    "imports",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contributes: { imports: documentTemplateImportTargets },
  contract,
  build,
};
