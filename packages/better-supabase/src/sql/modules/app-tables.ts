import type { BlockScope } from "../../config/blocks.ts";
import type {
  AppColumnConfig,
  AppReference,
  AppTableConfig,
} from "../../config/types/app-tables.ts";
import type { ModuleContext, ModuleIdType } from "../context.ts";
import type { ModuleFile, ModuleLayout } from "../module-types.ts";

import { AUTH_USERS } from "../../config/app-tables.ts";
import { CONFIG_DEFAULTS } from "../../config/defaults.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { moduleContext } from "../module-context.ts";
import { revokeTable } from "../shared.ts";

/**
 * The `module` of the files `renderModules` writes for `appTables`. App
 * tables aren't a block: no `SQL_MODULES` entry, no preset, no row in
 * `better_supabase.modules` (ADR 0040).
 */
export const APP_TABLES_MODULE = "app-tables";

/** The first line after the title of the app tables schema file. */
export const APP_TABLES_MARKER = "-- @bs-app-tables";

const SCHEMA = "public";
const COMMANDS = ["select", "insert", "update", "delete"] as const;

/** A literal of each scope id type no tenant holds, for the RLS test. */
const FOREIGN_ID: Readonly<Record<ModuleIdType, string>> = {
  uuid: "gen_random_uuid()",
  text: "'bs-app-tables-test'",
  bigint: "-1",
  integer: "-1",
};

interface ScopeColumn {
  readonly name: string;
  readonly definition: string;
  readonly idType: ModuleIdType;
}

interface AppTable {
  readonly name: string;
  readonly config: AppTableConfig;
  readonly ctx: ModuleContext;
  readonly scope: ScopeColumn | undefined;
  /** Whether `expose` sets the table's grants instead. */
  readonly exposed: boolean;
}

const qualified = (table: string): string =>
  `${sqlIdent(SCHEMA)}.${sqlIdent(table)}`;

function scopeOf(table: AppTableConfig, layout: ModuleLayout): BlockScope {
  switch (table.scope) {
    case "user":
    case "none": {
      return table.scope;
    }

    case undefined:
    case "inherit": {
      return layout.scope ?? "tenant";
    }

    default: {
      const never: never = table.scope;

      throw new TypeError(`Unknown app table scope "${String(never)}"`);
    }
  }
}

function scopeColumn(
  name: string,
  ctx: ModuleContext,
): ScopeColumn | undefined {
  switch (ctx.scope.kind) {
    case "tenant": {
      if (!ctx.installed("tenant")) {
        throw new TypeError(
          `appTables.${name}: tenant scope needs the tenant block, which checks membership; add it to blocks, or set the table's scope to "user" or "none"`,
        );
      }

      // Without the organizations block the tenant table is the app's own,
      // so the column stays a plain id, as the blocks' tenant columns are.
      const references = ctx.installed("organizations")
        ? (() => {
            const organizations = ctx.of("organizations");

            return ` references ${organizations.table("organizations")} (${organizations.col("organizations", "id")}) on delete cascade`;
          })()
        : "";

      return {
        name: ctx.naming.rename("organization_id"),
        definition: `${ctx.scope.column()}${references}`,
        idType: ctx.idType,
      };
    }

    case "user": {
      return {
        name: "user_id",
        definition: `${ctx.scope.column()} references auth.users (id) on delete cascade`,
        idType: "uuid",
      };
    }

    case "none": {
      return undefined;
    }

    default: {
      const never: never = ctx.scope.kind;

      throw new TypeError(`Unknown scope "${String(never)}"`);
    }
  }
}

function referenceSql(
  where: string,
  reference: AppReference,
  ctx: ModuleContext,
): string {
  const onDelete =
    reference.onDelete === undefined ? "" : ` on delete ${reference.onDelete}`;

  if ("block" in reference) {
    const { block, table } = reference;

    if (!ctx.installed(block)) {
      throw new TypeError(
        `${where}.references: the ${block} block is not installed; add it to blocks`,
      );
    }

    const target = ctx.of(block);

    if (!target.names.tables[table]) {
      throw new TypeError(
        `${where}.references: the ${block} block has no table "${table}" (${Object.keys(target.names.tables).join(", ") || "it has no tables"})`,
      );
    }

    if (!target.hasTable(table) || !target.has(table, "id")) {
      throw new TypeError(
        `${where}.references: the ${block} block's ${table} table has no id column to reference`,
      );
    }

    return ` references ${target.table(table)} (${target.col(table, "id")})${onDelete}`;
  }

  return reference.table === AUTH_USERS
    ? ` references auth.users (id)${onDelete}`
    : ` references ${qualified(reference.table)} (id)${onDelete}`;
}

function columnSql(
  where: string,
  name: string,
  column: AppColumnConfig,
  ctx: ModuleContext,
): string {
  return [
    `${sqlIdent(name)} ${column.type}`,
    column.nullable === false ? " not null" : "",
    column.default === undefined ? "" : ` default ${column.default}`,
    column.unique === true ? " unique" : "",
    column.references === undefined
      ? ""
      : referenceSql(where, column.references, ctx),
  ].join("");
}

function createSql(table: AppTable): string {
  const timestamps = table.config.timestamps !== false;

  const columns = [
    "id uuid primary key default gen_random_uuid()",
    ...(table.scope
      ? [`${sqlIdent(table.scope.name)} ${table.scope.definition}`]
      : []),
    ...(timestamps
      ? [
          "created_at timestamptz not null default now()",
          "updated_at timestamptz not null default now()",
        ]
      : []),
  ];

  return `create table if not exists ${qualified(table.name)} (
  ${columns.join(",\n  ")}
);`;
}

function columnsSql(table: AppTable): string {
  return Object.entries(table.config.columns ?? {})
    .map(
      ([name, column]) =>
        `alter table ${qualified(table.name)} add column if not exists ${columnSql(`appTables.${table.name}.columns.${name}`, name, column, table.ctx)};`,
    )
    .join("\n");
}

function indexesSql(table: AppTable): string {
  const indexed = [
    ...(table.scope ? [table.scope.name] : []),
    ...Object.entries(table.config.columns ?? {})
      .filter(
        ([, column]) =>
          column.references !== undefined && column.unique !== true,
      )
      .map(([name]) => name),
  ];

  return indexed
    .map(
      (column) =>
        `create index if not exists ${sqlIdent(`${table.name}_${column}_idx`)} on ${qualified(table.name)} (${sqlIdent(column)});`,
    )
    .join("\n");
}

/**
 * The rows a caller reaches: per tenant, rows of a tenant they are a member
 * of; per user, their own rows. `undefined` in `none` scope, where only the
 * service role writes.
 */
function ownRows(table: AppTable): string | undefined {
  const { ctx, scope } = table;

  if (!scope) {
    return undefined;
  }

  const column = sqlIdent(scope.name);

  return ctx.scope.kind === "tenant"
    ? `${column} in (select ${ctx.scope.members()})`
    : ctx.scope.check(column, "null");
}

function policiesSql(table: AppTable): string {
  const target = qualified(table.name);
  const own = ownRows(table);

  const policy = (command: (typeof COMMANDS)[number], body: string): string => {
    const name = sqlIdent(`${table.name}_${command}`);

    return `drop policy if exists ${name} on ${target};
create policy ${name} on ${target} for ${command} to authenticated ${body};`;
  };

  if (own === undefined) {
    return policy("select", `using (${table.ctx.scope.check("id", "null")})`);
  }

  return [
    policy("select", `using (${own})`),
    policy("insert", `with check (${own})`),
    policy("update", `using (${own}) with check (${own})`),
    policy("delete", `using (${own})`),
  ].join("\n");
}

function grantsSql(table: AppTable): string {
  const target = qualified(table.name);

  if (table.exposed) {
    return `-- expose sets the grants on ${target}.`;
  }

  const privileges = table.scope ? "select, insert, update, delete" : "select";

  return `${revokeTable(target)}
grant ${privileges} on ${target} to authenticated;
grant all on ${target} to service_role;`;
}

function triggerSql(table: AppTable): string {
  if (table.config.timestamps === false || !table.ctx.installed("updated-at")) {
    return "";
  }

  const target = qualified(table.name);
  const trigger = table.ctx.trigger("updated_at");

  return `drop trigger if exists ${trigger} on ${target};
create trigger ${trigger} before update on ${target}
  for each row execute function better_supabase.set_updated_at();`;
}

function tableSql(table: AppTable): string {
  return [
    `alter table ${qualified(table.name)} enable row level security;`,
    grantsSql(table),
    policiesSql(table),
    indexesSql(table),
    triggerSql(table),
  ]
    .filter((part) => part !== "")
    .join("\n");
}

/** Throws when an app table has the name of a table an installed block keeps. */
function checkBlockTables(
  names: readonly string[],
  layout: ModuleLayout,
  installed: readonly string[],
): void {
  const taken = new Map<string, string>();

  for (const module of installed) {
    const ctx = moduleContext(module, layout, installed);

    if (ctx.mode === "custom") {
      continue;
    }

    for (const logical of Object.keys(ctx.names.tables)) {
      if (ctx.hasTable(logical)) {
        taken.set(ctx.tableName(logical).name, module);
      }
    }
  }

  for (const name of names) {
    const module = taken.get(name);

    if (module !== undefined) {
      throw new TypeError(
        `appTables.${name}: the ${module} block already keeps a table named ${name}; choose another name`,
      );
    }
  }
}

function isExposed(name: string, layout: ModuleLayout): boolean {
  return (layout.grants ?? []).some(
    (grant) => grant.table === name || grant.table === `${SCHEMA}.${name}`,
  );
}

function testSql(table: AppTable): string {
  const name = sqlString(table.name);
  const label = `${SCHEMA}.${table.name}`;
  const regclass = `${sqlString(qualified(table.name))}::regclass`;
  const policies = table.scope ? COMMANDS : (["select"] as const);

  const checks = [
    `select extensions.has_table('${SCHEMA}', ${name}, ${sqlString(`${label} exists`)});`,
    `select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = ${regclass}), ${sqlString(`${label} has row level security on`)});`,
    `select extensions.policies_are('${SCHEMA}', ${name}, array[${policies.map((command) => sqlString(`${table.name}_${command}`)).join(", ")}], ${sqlString(`${label} has the policies for its scope`)});`,
  ];

  if (!table.exposed) {
    checks.push(
      `select extensions.table_privs_are('${SCHEMA}', ${name}, 'anon', array[]::text[], ${sqlString(`anon has no privileges on ${label}`)});`,
      `select extensions.table_privs_are('${SCHEMA}', ${name}, 'authenticated', array[${(table.scope ? ["DELETE", "INSERT", "SELECT", "UPDATE"] : ["SELECT"]).map((privilege) => sqlString(privilege)).join(", ")}], ${sqlString(`authenticated has the privileges for its scope on ${label}`)});`,
    );
  }

  const behaviour = table.scope
    ? [
        `select extensions.is((select count(*)::integer from ${qualified(table.name)} where not (${ownRows(table) ?? "true"})), 0, ${sqlString(`a signed-in user reads only the rows of ${label} their scope reaches`)});`,
        `select extensions.throws_ok($$insert into ${qualified(table.name)} (${sqlIdent(table.scope.name)}) values (${FOREIGN_ID[table.scope.idType]})$$, '42501', null, ${sqlString(`a signed-in user cannot insert a row of ${label} outside their scope`)});`,
      ]
    : [
        `select extensions.throws_ok($$insert into ${qualified(table.name)} default values$$, '42501', null, ${sqlString(`a signed-in user cannot write ${label}; only the service role does`)});`,
      ];

  return `${checks.join("\n")}

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
${behaviour.join("\n")}
reset role;`;
}

/**
 * The files for `layout.appTables`: one schema file that creates every app
 * table in `public` (implicit columns first, then each column with `add
 * column if not exists`, so a later column reaches an existing table),
 * with row level security, the grants and policies of its scope, indexes
 * on the scope and reference columns, and the `updated_at` trigger when
 * the `updated-at` block is installed; and one pgTAP file that checks the
 * policies and grants. Empty without app tables. `installed` is every
 * block module `renderModules` resolved.
 */
export function appTablesFiles(
  layout: ModuleLayout,
  installed: readonly string[],
): ModuleFile[] {
  const entries = Object.entries(layout.appTables ?? {});

  if (entries.length === 0) {
    return [];
  }

  checkBlockTables(
    entries.map(([name]) => name),
    layout,
    installed,
  );

  const tables = entries.map(([name, config]): AppTable => {
    const ctx = moduleContext(
      APP_TABLES_MODULE,
      { ...layout, scope: scopeOf(config, layout) },
      installed,
    );

    return {
      name,
      config,
      ctx,
      scope: scopeColumn(name, ctx),
      exposed: isExposed(name, layout),
    };
  });

  const title = `-- better-supabase module: app-tables${layout.version ? ` (${layout.version})` : ""}`;

  const managed = [
    "-- Managed by `better-supabase sql sync`; re-running it overwrites this file.",
    "-- Change it through `appTables` in better-supabase.config.ts.",
  ];

  const header = [
    title,
    APP_TABLES_MARKER,
    "-- The tables the app owns, from `appTables`, in public.",
    ...managed,
  ].join("\n");

  const body = [
    tables.map((table) => createSql(table)).join("\n\n"),
    tables
      .map((table) => columnsSql(table))
      .filter((part) => part !== "")
      .join("\n\n"),
    ...tables.map((table) => tableSql(table)),
  ]
    .filter((part) => part !== "")
    .join("\n\n");

  const dir = (layout.dir ?? CONFIG_DEFAULTS.sql.dir).replace(/\/$/, "");
  const prefix = layout.prefix ?? CONFIG_DEFAULTS.sql.prefix;

  const testsDir = (layout.testsDir ?? CONFIG_DEFAULTS.sql.testsDir).replace(
    /\/$/,
    "",
  );

  const plan = tables
    .map((table) => testSql(table))
    .join("\n\n")
    .split("\n")
    .filter((line) => /^select extensions\.(?!plan)/.test(line)).length;

  return [
    {
      module: APP_TABLES_MODULE,
      kind: "schema",
      path: `${dir}/${prefix}_app_tables.sql`,
      contents: `${header}\n\n${body}\n`,
    },
    {
      module: APP_TABLES_MODULE,
      kind: "test",
      path: `${testsDir}/900_better_supabase_app_tables.test.sql`,
      contents: `${title}\n-- @bs-module-test ${APP_TABLES_MODULE}\n${managed.join("\n")}\n\nbegin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(${String(plan)});

${tables.map((table) => testSql(table)).join("\n\n")}

select * from extensions.finish();
rollback;\n`,
    },
  ];
}
