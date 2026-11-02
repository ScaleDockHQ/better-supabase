import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, raise, schemaPreamble, serviceGrant } from "../shared.ts";

const VERSIONS = {
  id: "id",
  tenant: "organization_id",
  name: "name",
  version: "version",
  template: "template",
  variables: "variables",
  createdAt: "created_at",
} as const;

const LABELS = {
  tenant: "organization_id",
  name: "name",
  label: "label",
  version: "version",
  updatedAt: "updated_at",
} as const;

const NAMES: BlockSqlNames = {
  options: ["maxBytes"],
  tables: {
    versions: {
      name: "prompt_versions",
      columns: VERSIONS,
      lifecycle: { tenant: "tenant" },
      app: {},
      optional: ["createdAt"],
    },
    labels: {
      name: "prompt_labels",
      columns: LABELS,
      lifecycle: { tenant: "tenant" },
      app: {},
      optional: ["updatedAt"],
    },
  },
};

function build(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);

  const v = (column: keyof typeof VERSIONS): string =>
    ctx.col("versions", column);

  const l = (column: keyof typeof LABELS): string => ctx.col("labels", column);
  const versions = ctx.table("versions");
  const labels = ctx.table("labels");
  const versionsName = ctx.tableName("versions").name;
  const labelsName = ctx.tableName("labels").name;
  const maxBytes = ctx.number("maxBytes", 100 * 1024);

  if (!Number.isInteger(maxBytes) || maxBytes < 1) {
    throw new TypeError(
      "blocks.prompts.options.maxBytes must be a whole number of bytes",
    );
  }

  const hasCreated = ctx.has("versions", "createdAt");
  const hasUpdated = ctx.has("labels", "updatedAt");

  const versionJson = (row: string): string =>
    `jsonb_build_object(${Object.entries(VERSIONS)
      .map(
        ([logical, key]) =>
          `'${key}', ${ctx.has("versions", logical) ? `${row}.${ctx.col("versions", logical)}` : "null"}`,
      )
      .join(", ")})`;

  const key = (alias: string, column: string): string =>
    `coalesce(${alias}.${column}::text, '')`;

  const nameCheck = `^[a-z0-9][a-z0-9_.:/-]{0,127}$`;
  const labelCheck = `^[a-z0-9][a-z0-9_-]{0,63}$`;

  return `${schemaPreamble(ctx)}
-- Prompt templates the application versions by name, per tenant or for the
-- whole system (tenant is null). A version never changes once saved; a label
-- such as production points at one version. Templates can hold instructions
-- and secrets, so only the service role reads and writes them.
create table if not exists ${versions} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${id},
  ${v("name")} text not null check (${v("name")} ~ '${nameCheck}'),
  ${v("version")} integer not null check (${v("version")} >= 1),
  ${v("template")} text not null check (length(${v("template")}) between 1 and ${maxBytes}),
  ${v("variables")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${v("variables")}) = 'array')${hasCreated ? `,\n  ${v("createdAt")} timestamptz not null default now()` : ""}
);
create unique index if not exists ${sqlIdent(`bsb_${versionsName}_key`)} on ${versions} ((coalesce(${v("tenant")}::text, '')), ${v("name")}, ${v("version")});
create index if not exists ${sqlIdent(`${versionsName}_tenant_idx`)} on ${versions} (${v("tenant")});
${lockTable(versions)}

create table if not exists ${labels} (
  ${l("tenant")} ${id},
  ${l("name")} text not null,
  ${l("label")} text not null check (${l("label")} ~ '${labelCheck}'),
  ${l("version")} integer not null check (${l("version")} >= 1)${hasUpdated ? `,\n  ${l("updatedAt")} timestamptz not null default now()` : ""}
);
create unique index if not exists ${sqlIdent(`bsb_${labelsName}_key`)} on ${labels} ((coalesce(${l("tenant")}::text, '')), ${l("name")}, ${l("label")});
create index if not exists ${sqlIdent(`${labelsName}_tenant_idx`)} on ${labels} (${l("tenant")});
${lockTable(labels)}

-- Creates template as the next version of name and returns it. A label moves to
-- the new version in the same call.
create or replace function ${fn("create_prompt_version")}(name text, template text, tenant ${id} default null, variables jsonb default '[]'::jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${versions}%rowtype;
  v_next integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(create_prompt_version.tenant::text, '') || ':' || create_prompt_version.name, 0));
  select coalesce(max(x.${v("version")}), 0) + 1 into v_next from ${versions} x
  where ${key("x", v("tenant"))} = coalesce(create_prompt_version.tenant::text, '') and x.${v("name")} = create_prompt_version.name;
  insert into ${versions} (${v("tenant")}, ${v("name")}, ${v("version")}, ${v("template")}, ${v("variables")})
  values (create_prompt_version.tenant, create_prompt_version.name, v_next, create_prompt_version.template, coalesce(create_prompt_version.variables, '[]'::jsonb))
  returning * into v_row;
  if create_prompt_version.label is not null then
    insert into ${labels} (${l("tenant")}, ${l("name")}, ${l("label")}, ${l("version")})
    values (create_prompt_version.tenant, create_prompt_version.name, create_prompt_version.label, v_next)
    on conflict ((coalesce(${l("tenant")}::text, '')), ${l("name")}, ${l("label")}) do update set
      ${l("version")} = excluded.${l("version")}${hasUpdated ? `,\n      ${l("updatedAt")} = now()` : ""};
  end if;
  return ${versionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("create_prompt_version")}(text, text, ${id}, jsonb, text)`)}

-- The version of name that label (default production) points at, or the
-- exact version when one is given. A tenant's own prompt wins over the
-- system prompt of the same name. Null when there is none.
create or replace function ${fn("get_prompt")}(name text, label text default 'production', version integer default null, tenant ${id} default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${versions}%rowtype;
begin
  select x.* into v_row from ${versions} x
  where x.${v("name")} = get_prompt.name
    and (x.${v("tenant")} is null or x.${v("tenant")} = get_prompt.tenant)
    and (
      (get_prompt.version is not null and x.${v("version")} = get_prompt.version)
      or (get_prompt.version is null and exists (
        select 1 from ${labels} y
        where ${key("y", l("tenant"))} = ${key("x", v("tenant"))}
          and y.${l("name")} = x.${v("name")}
          and y.${l("label")} = get_prompt.label
          and y.${l("version")} = x.${v("version")}
      ))
    )
  order by (x.${v("tenant")} is null), x.${v("version")} desc
  limit 1;
  if not found then
    return null;
  end if;
  return ${versionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("get_prompt")}(text, text, integer, ${id})`)}

-- Points label at an existing version of name and returns the version.
create or replace function ${fn("set_prompt_label")}(name text, label text, version integer, tenant ${id} default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${versions}%rowtype;
begin
  select x.* into v_row from ${versions} x
  where x.${v("name")} = set_prompt_label.name
    and x.${v("version")} = set_prompt_label.version
    and ${key("x", v("tenant"))} = coalesce(set_prompt_label.tenant::text, '');
  if not found then
    ${raise("No version % of prompt %", "P0002", "PROMPT_NOT_FOUND", "set_prompt_label.version, set_prompt_label.name")}
  end if;
  insert into ${labels} (${l("tenant")}, ${l("name")}, ${l("label")}, ${l("version")})
  values (set_prompt_label.tenant, set_prompt_label.name, set_prompt_label.label, set_prompt_label.version)
  on conflict ((coalesce(${l("tenant")}::text, '')), ${l("name")}, ${l("label")}) do update set
    ${l("version")} = excluded.${l("version")}${hasUpdated ? `,\n    ${l("updatedAt")} = now()` : ""};
  return ${versionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("set_prompt_label")}(text, text, integer, ${id})`)}

-- Every version of name for a tenant (or the system when tenant is null),
-- newest first, each with the labels that point at it.
create or replace function ${fn("list_prompt_versions")}(name text, tenant ${id} default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(${versionJson("x")} || jsonb_build_object('labels', coalesce((
      select jsonb_agg(y.${l("label")} order by y.${l("label")}) from ${labels} y
      where ${key("y", l("tenant"))} = ${key("x", v("tenant"))}
        and y.${l("name")} = x.${v("name")} and y.${l("version")} = x.${v("version")}
    ), '[]'::jsonb)) order by x.${v("version")} desc), '[]'::jsonb)
    from ${versions} x
    where x.${v("name")} = list_prompt_versions.name
      and ${key("x", v("tenant"))} = coalesce(list_prompt_versions.tenant::text, '')
  );
end;
$$;
${serviceGrant(`${fn("list_prompt_versions")}(text, ${id})`)}`;
}

export const PROMPTS: BlockSqlDefinition = {
  name: "prompts",
  title: "Prompts",
  description:
    "Versioned prompt templates by name, per tenant or for the whole system, with labels such as production that point at one version; only the service role reads and writes them.",
  requires: [],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
