import type { BsbTag } from "./bsb-tags.ts";

import { fillTemplate, templatePlaceholders } from "../core/access-sql.ts";
import { sqlString } from "../core/template.ts";
import { listBody, listDeclare } from "./list-template.ts";

/**
 * The `@bsb` tags that render SQL beyond a single call (ADR 0637): `access`
 * policies, a keyset `list` function and an `idempotency` index. `table enable`
 * writes each as a block between marker comments in the table's file, so a
 * later run replaces it instead of adding a second copy.
 */
export const RENDERED_FEATURES = ["access", "list", "idempotency"] as const;

export type RenderedFeature = (typeof RENDERED_FEATURES)[number];

export function isRenderedFeature(value: string): value is RenderedFeature {
  return RENDERED_FEATURES.some((feature) => feature === value);
}

/** What a tag may assume of the authorization provider. */
export interface TagRenderOptions {
  /**
   * The provider's `functions.canIn` template. Without it the tag calls
   * `better_supabase.tenant_ids_with`, which every provider answers through
   * `idsWith`.
   */
  readonly canIn?: string | undefined;
  /**
   * The provider's `functions.actorMayWrite` template. Without it the tag calls
   * `better_supabase.actor_may_write()`.
   */
  readonly actorMayWrite?: string | undefined;
  /** The tenant scope's name, for `{scope}`. Defaults to `organization`. */
  readonly scope?: string | undefined;
}

const IDENTIFIER = /^[a-z_][a-z0-9_]*$/u;

function identifier(value: string, what: string): string {
  if (!IDENTIFIER.test(value)) {
    throw new TypeError(
      `@bsb ${what}: "${value}" is not a lower case identifier`,
    );
  }

  return value;
}

const quote = (value: string): string => `"${value}"`;

function arg(tag: BsbTag, name: string): string | undefined {
  const value = tag.args[name];

  return value === true ? undefined : value;
}

function list(tag: BsbTag, name: string): string[] {
  return (arg(tag, name) ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item !== "");
}

/** The tenant column, `false` for none. */
function tenantColumn(tag: BsbTag): string | undefined {
  const value = arg(tag, "tenant");

  return value === "false"
    ? undefined
    : identifier(value ?? "tenant_id", "tenant");
}

/** The SQL type a column name suggests, for a cursor value. */
function typeOfColumn(name: string): string {
  if (name === "id" || name.endsWith("_id")) {
    return "uuid";
  }

  if (name.endsWith("_at")) {
    return "timestamptz";
  }

  if (name.endsWith("_on") || name === "date") {
    return "date";
  }

  if (/^(sequence|position|rank|count|number|version)$/u.test(name)) {
    return "bigint";
  }

  return "text";
}

const CAST_TYPES = new Set([
  "uuid",
  "text",
  "timestamptz",
  "date",
  "bigint",
  "integer",
  "numeric",
  "boolean",
]);

function castType(value: string, what: string): string {
  if (!CAST_TYPES.has(value)) {
    throw new TypeError(
      `@bsb ${what}: "${value}" is not a type; use ${[...CAST_TYPES].join(", ")}`,
    );
  }

  return value;
}

const OPERATIONS = ["read", "create", "update", "delete"] as const;

function accessBlock(
  schema: string,
  table: string,
  tag: BsbTag,
  options: TagRenderOptions,
): string {
  const target = `${quote(schema)}.${quote(table)}`;
  const column = tenantColumn(tag);

  if (column === undefined) {
    throw new TypeError(
      "@bsb access needs a tenant column; set tenant=<column> (the default is tenant_id)",
    );
  }

  const permissions = OPERATIONS.flatMap((operation) => {
    const permission = arg(tag, operation);

    return permission === undefined ? [] : [[operation, permission] as const];
  });

  if (permissions.length === 0) {
    throw new TypeError(
      "@bsb access needs at least one of read=, create=, update= or delete= with a permission key",
    );
  }

  const scope = options.scope ?? "organization";

  const can = (permission: string): string => {
    if (options.canIn === undefined) {
      return `${quote(column)} in (select better_supabase.tenant_ids_with(${sqlString(permission)}))`;
    }

    return `(${fillTemplate("authorization.functions.canIn", options.canIn, {
      permission: sqlString(permission),
      tenant: quote(column),
      scope,
    })})`;
  };

  let guard = "";

  if (tag.args["actor-guard"] === true) {
    const template = options.actorMayWrite;

    if (template !== undefined && templatePlaceholders(template).length > 0) {
      throw new TypeError(
        "authorization.functions.actorMayWrite takes no placeholders",
      );
    }

    guard = ` and (${template === undefined ? "better_supabase.actor_may_write()" : fillTemplate("authorization.functions.actorMayWrite", template, {})})`;
  }

  const statements = permissions.map(([operation, permission]) => {
    const name = quote(`bsb_access_${table}_${operation}`);
    const header = `create policy ${name} on ${target}`;
    const check = can(permission);

    switch (operation) {
      case "read": {
        return `${header}\n  for select to authenticated\n  using (${check});`;
      }

      case "create": {
        return `${header}\n  for insert to authenticated\n  with check (${check}${guard});`;
      }

      case "update": {
        return `${header}\n  for update to authenticated\n  using (${check}${guard})\n  with check (${check}${guard});`;
      }

      case "delete": {
        return `${header}\n  for delete to authenticated\n  using (${check}${guard});`;
      }

      default: {
        operation satisfies never;

        return "";
      }
    }
  });

  return [
    `alter table ${target} enable row level security;`,
    ...statements,
  ].join("\n");
}

function idempotencyBlock(schema: string, table: string, tag: BsbTag): string {
  const column = identifier(arg(tag, "column") ?? "idempotency_key", "column");
  const tenant = tenantColumn(tag);
  const keys = tenant === undefined ? [column] : [tenant, column];

  return `create unique index ${quote(`bsb_${table}_idempotency_key`)} on ${quote(schema)}.${quote(table)} (${keys.map(quote).join(", ")}) where ${quote(column)} is not null;`;
}

interface Sort {
  readonly column: string;
  readonly dir: "asc" | "desc";
  readonly type: string;
}

function sorts(tag: BsbTag): Sort[] {
  const entries = list(tag, "sort");

  return (entries.length === 0 ? ["created_at:desc"] : entries).map((entry) => {
    const [column = "", dir = "asc", type] = entry.split(":");

    if (dir !== "asc" && dir !== "desc") {
      throw new TypeError(
        `@bsb list: sort "${entry}" has direction "${dir}"; use asc or desc`,
      );
    }

    const name = identifier(column, "sort");

    return {
      column: name,
      dir,
      type: castType(type ?? typeOfColumn(name), "list"),
    };
  });
}

function listBlock(schema: string, table: string, tag: BsbTag): string {
  const target = `${quote(schema)}.${quote(table)}`;
  const name = identifier(arg(tag, "name") ?? `list_${table}`, "name");
  const fn = `${quote(schema)}.${quote(name)}`;
  const tenant = tenantColumn(tag);
  const tenantType = castType(arg(tag, "tenant-type") ?? "uuid", "list");
  const idColumn = identifier(arg(tag, "id") ?? "id", "id");
  const idType = castType(arg(tag, "id-type") ?? "uuid", "list");

  const search = list(tag, "search").map((column) =>
    identifier(column, "search"),
  );

  const filters = list(tag, "filter").map((entry) => {
    const [column = "", type] = entry.split(":");
    const named = identifier(column, "filter");

    return {
      column: named,
      type: castType(type ?? typeOfColumn(named), "list"),
    };
  });

  const sort = sorts(tag);

  const keys = [
    ...sort,
    ...(sort.some((each) => each.column === idColumn)
      ? []
      : [{ column: idColumn, dir: "asc" as const, type: idType }]),
  ];

  const invalid = (message: string): string =>
    `raise exception ${sqlString(message)} using errcode = '22023';`;

  const where = [
    ...(tenant === undefined
      ? []
      : [`(${name}.tenant is null or x.${quote(tenant)} = ${name}.tenant)`]),
    ...filters.map(
      (filter) =>
        `(not v_filters ? ${sqlString(filter.column)} or x.${quote(filter.column)} = (v_filters ->> ${sqlString(filter.column)})::${filter.type})`,
    ),
    ...(search.length === 0
      ? []
      : [
          `(v_search is null or ${search.map((column) => `x.${quote(column)} ilike v_search`).join(" or ")})`,
        ]),
  ];

  const template = {
    name,
    from: target,
    alias: "x",
    where,
    keys: keys.map((key) => ({
      expr: `x.${quote(key.column)}`,
      dir: key.dir,
      type: key.type,
    })),
    rowJson: "to_jsonb(x)",
    invalid,
  } as const;

  const params =
    tenant === undefined
      ? "filters jsonb default '{}'::jsonb"
      : `tenant ${tenantType} default null, filters jsonb default '{}'::jsonb`;

  const signature = tenant === undefined ? "jsonb" : `${tenantType}, jsonb`;

  const searchVariable =
    search.length === 0
      ? ""
      : `  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%' end;\n`;

  const indexKeys = [
    ...(tenant === undefined ? [] : [quote(tenant)]),
    ...keys.map(
      (key) => `${quote(key.column)}${key.dir === "desc" ? " desc" : ""}`,
    ),
  ];

  const indexes = [
    `create index ${quote(`bsb_${table}_list_idx`)} on ${target} (${indexKeys.join(", ")});`,
    ...search.map(
      (column) =>
        `create index ${quote(`bsb_${table}_${column}_trgm_idx`)} on ${target} using gin (${quote(column)} extensions.gin_trgm_ops);`,
    ),
  ];

  return `-- Keyset page of ${schema}.${table}: filters is { ${[
    ...(search.length === 0 ? [] : ["search"]),
    ...filters.map((filter) => filter.column),
    "limit",
    "after",
    "offset",
    "paged",
    "total",
    "totalCap",
  ].join(", ")} }; row security decides the rows.
create or replace function ${fn}(${params})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(${name}.filters, '{}'::jsonb);
${searchVariable}  ${listDeclare(template)}
begin
  if jsonb_typeof(v_filters) <> 'object' then
    ${invalid("filters must be an object")}
  end if;
  ${listBody(template)}
end;
$$;
revoke execute on function ${fn}(${signature}) from public;
grant execute on function ${fn}(${signature}) to authenticated, service_role;
${indexes.join("\n")}`;
}

const begin = (feature: string): string => `-- @bsb-tag ${feature} begin`;
const end = (feature: string): string => `-- @bsb-tag ${feature} end`;

/**
 * The block `feature` renders for `schema.table` from `tag`: its statements
 * between the marker comments.
 */
export function renderTagBlock(
  feature: RenderedFeature,
  schema: string,
  table: string,
  tag: BsbTag,
  options: TagRenderOptions = {},
): string {
  identifier(schema, "schema");
  identifier(table, "table");

  const body = ((): string => {
    switch (feature) {
      case "access": {
        return accessBlock(schema, table, tag, options);
      }

      case "list": {
        return listBlock(schema, table, tag);
      }

      case "idempotency": {
        return idempotencyBlock(schema, table, tag);
      }

      default: {
        feature satisfies never;

        return "";
      }
    }
  })();

  return `${begin(feature)}\n${body}\n${end(feature)}`;
}

function blockPattern(feature: string): RegExp {
  return new RegExp(
    String.raw`\n*${begin(feature)}\n[\s\S]*?\n${end(feature)}\n?`,
    "u",
  );
}

/**
 * `sql` with the block of `feature` replaced by `block`, appended when the file
 * has none, or removed when `block` is undefined.
 */
export function setTagBlock(
  sql: string,
  feature: RenderedFeature,
  block: string | undefined,
): string {
  const pattern = blockPattern(feature);
  const found = pattern.test(sql);

  if (block === undefined) {
    return found ? sql.replace(pattern, "\n") : sql;
  }

  return found
    ? sql.replace(pattern, () => `\n\n${block}\n`)
    : `${sql.replace(/\n*$/u, "")}\n\n${block}\n`;
}
