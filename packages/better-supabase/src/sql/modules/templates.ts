import type { TemplatesEvents } from "../../blocks/templates/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import {
  addExtraColumns,
  extraFieldsArg,
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  sha256Hex,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { workflowParts } from "./templates-workflows.ts";

const EVENTS: BlockSqlEvents<TemplatesEvents> = {
  "template.published": {
    subject: "templates",
    payload: ["organizationId", "id", "versionId", "version", "type"],
  },
  "template.applied": {
    subject: "template-applications",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "id",
      "templateId",
      "versionId",
    ],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: [
    "before_template_save",
    "after_template_save",
    "before_template_apply",
    "after_template_apply",
  ],
  options: ["extraColumns"],
  tables: {
    templates: {
      name: "templates",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        scope: "scope",
        key: "key",
        type: "type",
        name: "name",
        language: "language",
        isDefault: "is_default",
        settings: "settings",
        forkedFrom: "forked_from",
        forkedFromVersion: "forked_from_version",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    versions: {
      name: "template_versions",
      columns: {
        id: "id",
        template: "template_id",
        version: "version",
        body: "body",
        hash: "hash",
        publishedAt: "published_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    applications: {
      name: "template_applications",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        template: "template_id",
        version: "version_id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        appliedBy: "applied_by",
        appliedAt: "applied_at",
      },
    },
    workflows: {
      name: "template_workflows",
      columns: {
        id: "id",
        template: "template_id",
        definition: "definition_id",
        inputs: "inputs",
        enabled: "enabled",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

/** The keys the template reads return next to the extra columns. */
const RESERVED = ["fields"] as const;

const TYPE_PATTERN = "'^[a-z][a-z0-9_.-]{0,63}$'";
const KEY_PATTERN = "'^[a-z0-9][a-z0-9_.-]{0,99}$'";
const LANGUAGE_PATTERN = "'^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$'";
const MAX_BODY_BYTES = 1_048_576;
const MAX_SETTINGS_BYTES = 65_536;

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("templates");
  const ver = ctx.table("versions");
  const app = ctx.table("applications");
  const ct = (column: string): string => ctx.col("templates", column);
  const cv = (column: string): string => ctx.col("versions", column);
  const ca = (column: string): string => ctx.col("applications", column);
  const read = ctx.permission("read", OPERATIONS["templates.read"]);
  const apply = ctx.permission("apply", OPERATIONS["templates.apply"]);
  const manage = ctx.permission("manage", OPERATIONS["templates.manage"]);
  const extras = ctx.extraColumns("templates", RESERVED);
  const extra = extraFieldsArg(extras);

  const builder = ctx.installed("workflow-editor")
    ? ctx.of("workflow-editor")
    : undefined;

  const schemas = ctx.installed("jsonb-schemas");

  // A system template only the service role changes; a tenant's needs
  // templates.manage there.
  const mayManage = (tenant: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.scope.can(tenant, manage)}))`;

  const readable = `${ct("tenant")} in (select ${ctx.scope.ids(read)})
    or (${ct("scope")} = 'system' and exists (select ${ctx.scope.ids(read)}))`;

  // The template's newest published version.
  const published = (template: string): string =>
    `(select y.${cv("version")} from ${ver} y where y.${cv("template")} = ${template} and y.${cv("publishedAt")} is not null order by y.${cv("version")} desc limit 1)`;

  const templateJson = (alias: string): string =>
    withExtraFields(
      `jsonb_build_object(
    'id', ${alias}.${ct("id")},
    'tenant', ${alias}.${ct("tenant")},
    'scope', ${alias}.${ct("scope")},
    'key', ${alias}.${ct("key")},
    'type', ${alias}.${ct("type")},
    'name', ${alias}.${ct("name")},
    'language', ${alias}.${ct("language")},
    'isDefault', ${alias}.${ct("isDefault")},
    'settings', ${alias}.${ct("settings")},
    'forkedFrom', ${alias}.${ct("forkedFrom")},
    'forkedFromVersion', ${alias}.${ct("forkedFromVersion")},
    'publishedVersion', ${published(`${alias}.${ct("id")}`)},
    'upstreamVersion', case when ${alias}.${ct("forkedFrom")} is not null then ${published(`${alias}.${ct("forkedFrom")}`)} end,
    'createdBy', ${alias}.${ct("createdBy")},
    'createdAt', ${alias}.${ct("createdAt")},
    'updatedAt', ${alias}.${ct("updatedAt")}
  )`,
      alias,
      extras,
    );

  const versionJson = (alias: string, full: boolean): string =>
    `jsonb_build_object(
    'id', ${alias}.${cv("id")},
    'template', ${alias}.${cv("template")},
    'version', ${alias}.${cv("version")},
    'hash', ${alias}.${cv("hash")},
    'publishedAt', ${alias}.${cv("publishedAt")},
    'createdBy', ${alias}.${cv("createdBy")},
    'createdAt', ${alias}.${cv("createdAt")}${
      full
        ? `,
    'body', ${alias}.${cv("body")}`
        : ""
    }
  )`;

  const applicationJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${ca("id")},
    'template', ${alias}.${ca("template")},
    'version', ${alias}.${ca("version")},
    'tenant', ${alias}.${ca("tenant")},
    'subjectType', ${alias}.${ca("subjectType")},
    'subjectId', ${alias}.${ca("subjectId")},
    'appliedBy', ${alias}.${ca("appliedBy")},
    'appliedAt', ${alias}.${ca("appliedAt")}
  )`;

  const workflows =
    builder === undefined
      ? undefined
      : workflowParts(ctx, { builder, schemas, mayManage });

  return `${schemaPreamble(ctx)}
create extension if not exists pgcrypto with schema extensions;

-- Templates of a type (an invoice, a project, an email): a tenant's own, or
-- a system starter (no tenant) that sync_templates keeps by key and tenants
-- fork. forked_from: the template and version a fork copied.
create table if not exists ${t} (
  ${ct("id")} uuid primary key default gen_random_uuid(),
  ${ct("tenant")} ${id},
  ${ct("scope")} text not null default 'tenant' check (${ct("scope")} in ('tenant', 'system')),
  ${ct("key")} text check (${ct("key")} ~ ${KEY_PATTERN}),
  ${ct("type")} text not null check (${ct("type")} ~ ${TYPE_PATTERN}),
  ${ct("name")} text not null check (length(${ct("name")}) between 1 and 200),
  ${ct("language")} text not null default 'en' check (${ct("language")} ~ ${LANGUAGE_PATTERN}),
  ${ct("isDefault")} boolean not null default false,
  ${ct("settings")} jsonb not null default '{}'::jsonb
    check (jsonb_typeof(${ct("settings")}) = 'object' and pg_column_size(${ct("settings")}) <= ${String(MAX_SETTINGS_BYTES)}),
  ${ct("forkedFrom")} uuid references ${t} (${ct("id")}) on delete set null,
  ${ct("forkedFromVersion")} integer check (${ct("forkedFromVersion")} > 0),
  ${ct("createdBy")} uuid references auth.users (id) on delete set null,
  ${ct("createdAt")} timestamptz not null default now(),
  ${ct("updatedAt")} timestamptz not null default now(),
  constraint templates_system_check check ((${ct("scope")} = 'system') = (${ct("tenant")} is null))
);${addExtraColumns(t, extras)}
create unique index if not exists templates_key_idx on ${t} (${ct("tenant")}, ${ct("key")}) nulls not distinct where ${ct("key")} is not null;
create unique index if not exists templates_default_idx on ${t} (${ct("tenant")}, ${ct("type")}, ${ct("language")}) nulls not distinct where ${ct("isDefault")};
create index if not exists templates_type_idx on ${t} (${ct("tenant")}, ${ct("type")});
create index if not exists templates_forked_from_idx on ${t} (${ct("forkedFrom")}) where ${ct("forkedFrom")} is not null;
create index if not exists templates_created_by_idx on ${t} (${ct("createdBy")});
${lockTable(t, { read: true })}
drop policy if exists templates_read on ${t};
create policy templates_read on ${t} for select to authenticated
  using (${readable});

-- Numbered snapshots of a template's body: at most one draft, and published
-- versions that never change. hash: the SHA-256 of the body as text.
create table if not exists ${ver} (
  ${cv("id")} uuid primary key default gen_random_uuid(),
  ${cv("template")} uuid not null references ${t} (${ct("id")}) on delete cascade,
  ${cv("version")} integer not null check (${cv("version")} > 0),
  ${cv("body")} jsonb not null check (pg_column_size(${cv("body")}) <= ${String(MAX_BODY_BYTES)}),
  ${cv("hash")} text not null,
  ${cv("publishedAt")} timestamptz,
  ${cv("createdBy")} uuid references auth.users (id) on delete set null,
  ${cv("createdAt")} timestamptz not null default now(),
  constraint template_versions_template_version_key unique (${cv("template")}, ${cv("version")})
);
create unique index if not exists template_versions_one_draft_idx on ${ver} (${cv("template")}) where ${cv("publishedAt")} is null;
create index if not exists template_versions_created_by_idx on ${ver} (${cv("createdBy")});
${lockTable(ver, { read: true })}
drop policy if exists template_versions_read on ${ver};
create policy template_versions_read on ${ver} for select to authenticated
  using (exists (select 1 from ${t} x where x.${ct("id")} = ${cv("template")}));

-- Each time a published version created a record, and which one.
create table if not exists ${app} (
  ${ca("id")} uuid primary key default gen_random_uuid(),
  ${ca("template")} uuid not null references ${t} (${ct("id")}) on delete cascade,
  ${ca("version")} uuid not null references ${ver} (${cv("id")}) on delete cascade,
  ${ca("tenant")} ${id} not null,
  ${ca("subjectType")} text not null check (length(${ca("subjectType")}) between 1 and 100),
  ${ca("subjectId")} text not null check (length(${ca("subjectId")}) between 1 and 200),
  ${ca("appliedBy")} uuid references auth.users (id) on delete set null,
  ${ca("appliedAt")} timestamptz not null default now()
);
create index if not exists template_applications_tenant_idx on ${app} (${ca("tenant")}, ${ca("appliedAt")} desc);
create index if not exists template_applications_template_idx on ${app} (${ca("template")});
create index if not exists template_applications_version_idx on ${app} (${ca("version")});
create index if not exists template_applications_subject_idx on ${app} (${ca("subjectType")}, ${ca("subjectId")});
create index if not exists template_applications_applied_by_idx on ${app} (${ca("appliedBy")});
${lockTable(app, { read: true })}
drop policy if exists template_applications_read on ${app};
create policy template_applications_read on ${app} for select to authenticated
  using (${ca("tenant")} in (select ${ctx.scope.ids(read)}));
${workflows?.ddl ?? ""}
-- Creates a template (template_id null) or renames it and replaces its
-- settings. tenant null saves a system template, which only the service
-- role may; a tenant's needs templates.manage there.
-- fields: the extra columns (blocks.templates.options.extraColumns) to set.
${extra.drop(fn("save_template"), `uuid, ${id}, text, text, text, jsonb`)}
create or replace function ${fn("save_template")}(template_id uuid, tenant ${id}, type text, name text, language text, settings jsonb${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${t}%rowtype;
begin
  if save_template.settings is not null and jsonb_typeof(save_template.settings) <> 'object' then
    ${fail("TEMPLATE_INVALID", "settings must be an object", "22023")}
  end if;
  if save_template.template_id is not null then
    select * into v_row from ${t} x where x.${ct("id")} = save_template.template_id for update;
    if not found or v_row.${ct("tenant")} is distinct from save_template.tenant then
      ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
    end if;
  end if;
  if not ${mayManage("save_template.tenant")} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not change templates here")}
  end if;
  if save_template.template_id is null and (save_template.type is null or save_template.type !~ ${TYPE_PATTERN}) then
    ${fail("TEMPLATE_INVALID", "type must be lower-case letters, digits, dots, dashes or underscores", "22023")}
  end if;
  if save_template.template_id is null and save_template.name is null then
    ${fail("TEMPLATE_INVALID", "A template needs a name", "22023")}
  end if;
  ${ctx.hook("before_template_save", [
    [id, "save_template.tenant"],
    ["text", `coalesce(save_template.type, v_row.${ct("type")})`],
    ["jsonb", "save_template.settings"],
  ])}
  if save_template.template_id is null then
    insert into ${t} (${ct("tenant")}, ${ct("scope")}, ${ct("type")}, ${ct("name")}, ${ct("language")}, ${ct("settings")}, ${ct("createdBy")})
    values (
      save_template.tenant,
      case when save_template.tenant is null then 'system' else 'tenant' end,
      save_template.type,
      save_template.name,
      coalesce(save_template.language, 'en'),
      coalesce(save_template.settings, '{}'::jsonb),
      (select auth.uid())
    )
    returning * into v_row;
  else
    update ${t} x set
      ${ct("name")} = coalesce(save_template.name, x.${ct("name")}),
      ${ct("language")} = coalesce(save_template.language, x.${ct("language")}),
      ${ct("settings")} = coalesce(save_template.settings, x.${ct("settings")}),
      ${ct("isDefault")} = x.${ct("isDefault")} and coalesce(save_template.language, x.${ct("language")}) = x.${ct("language")},
      ${ct("updatedAt")} = now()
    where x.${ct("id")} = save_template.template_id
    returning * into v_row;
  end if;${
    extras.length === 0
      ? ""
      : `${writeExtraColumns(t, extras, "save_template.fields", `x.${ct("id")} = v_row.${ct("id")}`)}
  select * into v_row from ${t} x where x.${ct("id")} = v_row.${ct("id")};`
  }
  ${ctx.hook("after_template_save", [["uuid", `v_row.${ct("id")}`]])}
  return ${templateJson("v_row")};
end;
$$;
${userGrant(`${fn("save_template")}(uuid, ${id}, text, text, text, jsonb${extra.type})`)}

-- The tenant's templates and the system ones (only the system ones without
-- a tenant), filtered by type and language, defaults first.
create or replace function ${fn("templates_list")}(tenant ${id}, type text, language text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${templateJson("x")}
    order by x.${ct("isDefault")} desc, x.${ct("scope")} desc, x.${ct("name")}, x.${ct("id")}), '[]'::jsonb)
  from ${t} x
  where (x.${ct("tenant")} = templates_list.tenant or x.${ct("scope")} = 'system')
    and (templates_list.type is null or x.${ct("type")} = templates_list.type)
    and (templates_list.language is null or x.${ct("language")} = templates_list.language)
$$;
${userGrant(`${fn("templates_list")}(${id}, text, text)`)}

-- One template with its newest published version and its draft, bodies
-- included; null when the caller can't read it.
create or replace function ${fn("template_get")}(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${templateJson("x")} || jsonb_build_object(
    'published', (select ${versionJson("y", true)} from ${ver} y
      where y.${cv("template")} = x.${ct("id")} and y.${cv("publishedAt")} is not null
      order by y.${cv("version")} desc limit 1),
    'draft', (select ${versionJson("y", true)} from ${ver} y
      where y.${cv("template")} = x.${ct("id")} and y.${cv("publishedAt")} is null))
  from ${t} x
  where x.${ct("id")} = template_get.template_id
$$;
${userGrant(`${fn("template_get")}(uuid)`)}

create or replace function ${fn("remove_template")}(template_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${t}%rowtype;
begin
  select * into v_row from ${t} x where x.${ct("id")} = remove_template.template_id;
  if not found then
    return false;
  end if;
  if not ${mayManage(`v_row.${ct("tenant")}`)} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not remove this template")}
  end if;
  delete from ${t} x where x.${ct("id")} = remove_template.template_id;
  return true;
end;
$$;
${userGrant(`${fn("remove_template")}(uuid)`)}

-- Saves body as the template's draft: updates the open one, or opens one
-- numbered after the last version.
create or replace function ${fn("save_template_draft")}(template_id uuid, body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl ${t}%rowtype;
  v_row ${ver}%rowtype;
begin
  select * into v_tpl from ${t} x where x.${ct("id")} = save_template_draft.template_id for update;
  if not found then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  if not ${mayManage(`v_tpl.${ct("tenant")}`)} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not edit this template")}
  end if;
  if save_template_draft.body is null then
    ${fail("TEMPLATE_INVALID", "A template version needs a body", "22023")}
  end if;
  update ${ver} x set
    ${cv("body")} = save_template_draft.body,
    ${cv("hash")} = ${sha256Hex("save_template_draft.body::text")}
  where x.${cv("template")} = save_template_draft.template_id and x.${cv("publishedAt")} is null
  returning * into v_row;
  if not found then
    insert into ${ver} (${cv("template")}, ${cv("version")}, ${cv("body")}, ${cv("hash")}, ${cv("createdBy")})
    values (
      save_template_draft.template_id,
      coalesce((select max(y.${cv("version")}) from ${ver} y where y.${cv("template")} = save_template_draft.template_id), 0) + 1,
      save_template_draft.body,
      ${sha256Hex("save_template_draft.body::text")},
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update ${t} x set ${ct("updatedAt")} = now() where x.${ct("id")} = save_template_draft.template_id;
  return ${versionJson("v_row", true)};
end;
$$;
${userGrant(`${fn("save_template_draft")}(uuid, jsonb)`)}

-- Publishes the template's draft. Applications use the newest published
-- version; published versions never change.
create or replace function ${fn("publish_template_version")}(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl ${t}%rowtype;
  v_row ${ver}%rowtype;
begin
  select * into v_tpl from ${t} x where x.${ct("id")} = publish_template_version.template_id for update;
  if not found then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  if not ${mayManage(`v_tpl.${ct("tenant")}`)} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not publish this template")}
  end if;
  update ${ver} x set ${cv("publishedAt")} = now()
  where x.${cv("template")} = publish_template_version.template_id and x.${cv("publishedAt")} is null
  returning * into v_row;
  if not found then
    ${fail("TEMPLATE_NO_DRAFT", "This template has no draft to publish", "P0002")}
  end if;
  update ${t} x set ${ct("updatedAt")} = now() where x.${ct("id")} = publish_template_version.template_id;
  ${ctx.record({
    type: "template.published",
    payload: `jsonb_build_object('organizationId', v_tpl.${ct("tenant")}, 'id', v_tpl.${ct("id")}, 'versionId', v_row.${cv("id")}, 'version', v_row.${cv("version")}, 'type', v_tpl.${ct("type")})`,
    subject: `'templates/' || v_tpl.${ct("id")}::text`,
    tenant: `v_tpl.${ct("tenant")}`,
    audit: {
      category: "configuration",
      targetType: "template",
      recordId: `v_tpl.${ct("id")}::text`,
      targetLabel: `v_tpl.${ct("name")}`,
    },
  })}
  return ${versionJson("v_row", true)};
end;
$$;
${userGrant(`${fn("publish_template_version")}(uuid)`)}

create or replace function ${fn("template_versions_list")}(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${versionJson("y", false)} order by y.${cv("version")} desc), '[]'::jsonb)
  from ${ver} y where y.${cv("template")} = template_versions_list.template_id
$$;
${userGrant(`${fn("template_versions_list")}(uuid)`)}

-- One default per tenant, type and language.
create or replace function ${fn("set_default_template")}(template_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${t}%rowtype;
begin
  select * into v_row from ${t} x where x.${ct("id")} = set_default_template.template_id for update;
  if not found then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  if not ${mayManage(`v_row.${ct("tenant")}`)} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not change this template")}
  end if;
  if set_default_template.on_default then
    update ${t} x set ${ct("isDefault")} = false, ${ct("updatedAt")} = now()
    where x.${ct("tenant")} is not distinct from v_row.${ct("tenant")}
      and x.${ct("type")} = v_row.${ct("type")} and x.${ct("language")} = v_row.${ct("language")}
      and x.${ct("isDefault")} and x.${ct("id")} <> v_row.${ct("id")};
  end if;
  update ${t} x set ${ct("isDefault")} = coalesce(set_default_template.on_default, false), ${ct("updatedAt")} = now()
  where x.${ct("id")} = set_default_template.template_id;
  return true;
end;
$$;
${userGrant(`${fn("set_default_template")}(uuid, boolean)`)}

-- Copies the newest published version of source (a system template, or one
-- in tenant) into a new template in tenant, published as its version 1, and
-- records the version it copied. templates.manage in tenant.
create or replace function ${fn("fork_template")}(source uuid, tenant ${id})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src ${t}%rowtype;
  v_version ${ver}%rowtype;
  v_row ${t}%rowtype;
begin
  select * into v_src from ${t} x where x.${ct("id")} = fork_template.source;
  if not found or not (v_src.${ct("scope")} = 'system' or v_src.${ct("tenant")} is not distinct from fork_template.tenant) then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  if fork_template.tenant is null or not ${mayManage("fork_template.tenant")} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not create templates here")}
  end if;
  select * into v_version from ${ver} y
  where y.${cv("template")} = fork_template.source and y.${cv("publishedAt")} is not null
  order by y.${cv("version")} desc limit 1;
  if not found then
    ${fail("TEMPLATE_NOT_PUBLISHED", "This template has no published version", "P0002")}
  end if;
  insert into ${t} (${ct("tenant")}, ${ct("scope")}, ${ct("type")}, ${ct("name")}, ${ct("language")}, ${ct("settings")}, ${ct("forkedFrom")}, ${ct("forkedFromVersion")}, ${ct("createdBy")})
  values (fork_template.tenant, 'tenant', v_src.${ct("type")}, v_src.${ct("name")}, v_src.${ct("language")}, v_src.${ct("settings")}, v_src.${ct("id")}, v_version.${cv("version")}, (select auth.uid()))
  returning * into v_row;
  insert into ${ver} (${cv("template")}, ${cv("version")}, ${cv("body")}, ${cv("hash")}, ${cv("publishedAt")}, ${cv("createdBy")})
  values (v_row.${ct("id")}, 1, v_version.${cv("body")}, v_version.${cv("hash")}, now(), (select auth.uid()));
${workflows?.forkCopy ?? ""}
  return ${templateJson("v_row")};
end;
$$;
${userGrant(`${fn("fork_template")}(uuid, ${id})`)}

-- Upserts the system templates by key from starters, a JSON array of
-- { key, type, name, language?, settings?, body }, and publishes a new
-- version of each whose body changed. Returns how many it published.
create or replace function ${fn("sync_templates")}(starters jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_starter jsonb;
  v_row ${t}%rowtype;
  v_hash text;
  v_version ${ver}%rowtype;
  v_count integer := 0;
begin
  if jsonb_typeof(sync_templates.starters) <> 'array' then
    ${fail("TEMPLATE_INVALID", "starters must be an array", "22023")}
  end if;
  for v_starter in select value from jsonb_array_elements(sync_templates.starters) loop
    if coalesce(v_starter ->> 'key', '') !~ ${KEY_PATTERN} or not (v_starter ? 'body') then
      ${fail("TEMPLATE_INVALID", "Each starter needs a key and a body", "22023")}
    end if;
    select * into v_row from ${t} x where x.${ct("tenant")} is null and x.${ct("key")} = v_starter ->> 'key' for update;
    if not found then
      insert into ${t} (${ct("tenant")}, ${ct("scope")}, ${ct("key")}, ${ct("type")}, ${ct("name")}, ${ct("language")}, ${ct("settings")})
      values (null, 'system', v_starter ->> 'key', v_starter ->> 'type', v_starter ->> 'name',
        coalesce(v_starter ->> 'language', 'en'), coalesce(v_starter -> 'settings', '{}'::jsonb))
      returning * into v_row;
    else
      update ${t} x set
        ${ct("type")} = coalesce(v_starter ->> 'type', x.${ct("type")}),
        ${ct("name")} = coalesce(v_starter ->> 'name', x.${ct("name")}),
        ${ct("language")} = coalesce(v_starter ->> 'language', x.${ct("language")}),
        ${ct("settings")} = coalesce(v_starter -> 'settings', x.${ct("settings")}),
        ${ct("updatedAt")} = now()
      where x.${ct("id")} = v_row.${ct("id")}
      returning * into v_row;
    end if;
    v_hash := ${sha256Hex("(v_starter -> 'body')::text")};
    if v_hash is distinct from (select y.${cv("hash")} from ${ver} y
        where y.${cv("template")} = v_row.${ct("id")} and y.${cv("publishedAt")} is not null
        order by y.${cv("version")} desc limit 1) then
      delete from ${ver} y where y.${cv("template")} = v_row.${ct("id")} and y.${cv("publishedAt")} is null;
      insert into ${ver} (${cv("template")}, ${cv("version")}, ${cv("body")}, ${cv("hash")}, ${cv("publishedAt")})
      values (
        v_row.${ct("id")},
        coalesce((select max(y.${cv("version")}) from ${ver} y where y.${cv("template")} = v_row.${ct("id")}), 0) + 1,
        v_starter -> 'body',
        v_hash,
        now()
      )
      returning * into v_version;
      v_count := v_count + 1;
      ${ctx.record({
        type: "template.published",
        payload: `jsonb_build_object('organizationId', null, 'id', v_row.${ct("id")}, 'versionId', v_version.${cv("id")}, 'version', v_version.${cv("version")}, 'type', v_row.${ct("type")})`,
        subject: `'templates/' || v_row.${ct("id")}::text`,
        audit: false,
      })}
    end if;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("sync_templates")}(jsonb)`)}

-- What applying template in tenant needs: the template, its newest
-- published version with the body, and the enabled workflow attachments,
-- each input checked against the published version's input_schema
-- (TEMPLATE_WORKFLOW_INPUT_INVALID). templates.apply in tenant.
create or replace function ${fn("template_apply_target")}(template_id uuid, tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl ${t}%rowtype;
  v_version ${ver}%rowtype;
  v_workflows jsonb := '[]'::jsonb;
begin
  if template_apply_target.tenant is null then
    ${fail("TEMPLATE_INVALID", "Applying a template needs a tenant", "22023")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.scope.can("template_apply_target.tenant", apply)}) then
    ${fail("TEMPLATE_FORBIDDEN", "You may not apply templates here")}
  end if;
  select * into v_tpl from ${t} x where x.${ct("id")} = template_apply_target.template_id;
  if not found or not (v_tpl.${ct("scope")} = 'system' or v_tpl.${ct("tenant")} = template_apply_target.tenant) then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  select * into v_version from ${ver} y
  where y.${cv("template")} = v_tpl.${ct("id")} and y.${cv("publishedAt")} is not null
  order by y.${cv("version")} desc limit 1;
  if not found then
    ${fail("TEMPLATE_NOT_PUBLISHED", "This template has no published version", "P0002")}
  end if;
${workflows?.applyTarget ?? ""}
  return jsonb_build_object(
    'template', ${templateJson("v_tpl")},
    'version', ${versionJson("v_version", true)},
    'workflows', v_workflows
  );
end;
$$;
${userGrant(`${fn("template_apply_target")}(uuid, ${id})`)}

-- Records that version of template created subject_type/subject_id in
-- tenant. templates.apply in tenant.
create or replace function ${fn("record_template_application")}(template_id uuid, version_id uuid, tenant ${id}, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl ${t}%rowtype;
  v_row ${app}%rowtype;
begin
  if record_template_application.tenant is null then
    ${fail("TEMPLATE_INVALID", "Applying a template needs a tenant", "22023")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.scope.can("record_template_application.tenant", apply)}) then
    ${fail("TEMPLATE_FORBIDDEN", "You may not apply templates here")}
  end if;
  select * into v_tpl from ${t} x where x.${ct("id")} = record_template_application.template_id;
  if not found or not (v_tpl.${ct("scope")} = 'system' or v_tpl.${ct("tenant")} = record_template_application.tenant) then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  if not exists (select 1 from ${ver} y where y.${cv("id")} = record_template_application.version_id
      and y.${cv("template")} = v_tpl.${ct("id")} and y.${cv("publishedAt")} is not null) then
    ${fail("TEMPLATE_NOT_PUBLISHED", "Not a published version of this template", "P0002")}
  end if;
  ${ctx.hook("before_template_apply", [
    [id, "record_template_application.tenant"],
    ["uuid", `v_tpl.${ct("id")}`],
    ["text", "record_template_application.subject_type"],
    ["text", "record_template_application.subject_id"],
  ])}
  insert into ${app} (${ca("template")}, ${ca("version")}, ${ca("tenant")}, ${ca("subjectType")}, ${ca("subjectId")}, ${ca("appliedBy")})
  values (v_tpl.${ct("id")}, record_template_application.version_id, record_template_application.tenant,
    record_template_application.subject_type, record_template_application.subject_id, (select auth.uid()))
  returning * into v_row;
  ${ctx.record({
    type: "template.applied",
    payload: `jsonb_build_object('organizationId', v_row.${ca("tenant")}, 'subjectType', v_row.${ca("subjectType")}, 'subjectId', v_row.${ca("subjectId")}, 'id', v_row.${ca("id")}, 'templateId', v_row.${ca("template")}, 'versionId', v_row.${ca("version")})`,
    subject: `'template-applications/' || v_row.${ca("id")}::text`,
    tenant: `v_row.${ca("tenant")}`,
    audit: {
      category: "data",
      targetType: "template_application",
      recordId: `v_row.${ca("id")}::text`,
      targetLabel: `v_tpl.${ct("name")}`,
    },
  })}
  ${ctx.hook("after_template_apply", [["uuid", `v_row.${ca("id")}`]])}
  return ${applicationJson("v_row")};
end;
$$;
${userGrant(`${fn("record_template_application")}(uuid, uuid, ${id}, text, text)`)}

-- The tenant's applications, newest first, of one template or onto one
-- subject when those are given.
create or replace function ${fn("template_applications_list")}(tenant ${id}, template_id uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.value order by r.at desc, r.id), '[]'::jsonb)
  from (
    select ${applicationJson("a")} as value, a.${ca("appliedAt")} as at, a.${ca("id")} as id
    from ${app} a
    where a.${ca("tenant")} = template_applications_list.tenant
      and (template_applications_list.template_id is null or a.${ca("template")} = template_applications_list.template_id)
      and (template_applications_list.subject_type is null or a.${ca("subjectType")} = template_applications_list.subject_type)
      and (template_applications_list.subject_id is null or a.${ca("subjectId")} = template_applications_list.subject_id)
    order by a.${ca("appliedAt")} desc, a.${ca("id")}
    limit 200
  ) r
$$;
${userGrant(`${fn("template_applications_list")}(${id}, uuid, text, text)`)}
${workflows?.functions ?? ""}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_template",
      args: [
        "uuid",
        "{id}",
        "text",
        "text",
        "text",
        "jsonb",
        ...extraFieldsArg(ctx.extraColumns("templates", RESERVED)).contract,
      ],
      returns: "jsonb",
    },
    {
      name: "templates_list",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    { name: "template_get", args: ["uuid"], returns: "jsonb" },
    { name: "remove_template", args: ["uuid"], returns: "boolean" },
    { name: "save_template_draft", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "publish_template_version", args: ["uuid"], returns: "jsonb" },
    { name: "template_versions_list", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_default_template",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "fork_template", args: ["uuid", "{id}"], returns: "jsonb" },
    { name: "sync_templates", args: ["jsonb"], returns: "integer" },
    { name: "template_apply_target", args: ["uuid", "{id}"], returns: "jsonb" },
    {
      name: "record_template_application",
      args: ["uuid", "uuid", "{id}", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "template_applications_list",
      args: ["{id}", "uuid", "text", "text"],
      returns: "jsonb",
    },
    ...(ctx.installed("workflow-editor")
      ? [
          {
            name: "attach_template_workflow",
            args: ["uuid", "uuid", "jsonb", "boolean"],
            returns: "jsonb",
          },
          {
            name: "detach_template_workflow",
            args: ["uuid", "uuid"],
            returns: "boolean",
          },
          { name: "template_workflows_list", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
  ];
}

export const TEMPLATES: BlockSqlDefinition = {
  name: "templates",
  scopes: ["tenant"],
  title: "Templates",
  description:
    "Typed, versioned templates (system starters and tenant forks) that create records, with merge fields and workflows started on each record they create.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit", "workflow-editor", "jsonb-schemas"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
