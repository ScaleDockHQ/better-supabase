import type { BlockScope } from "../../config/blocks.ts";
import type {
  AppColumnConfig,
  AppReference,
  AppTableConfig,
  AppTableEventKind,
} from "../../config/types/app-tables.ts";
import type { BlockSqlContext, BlockSqlIdType } from "../context.ts";
import type { BlockSqlFile, BlockSqlLayout } from "../module-types.ts";
import type { EnrichTable } from "./app-table-enrich.ts";
import type { SealTable } from "./app-table-seal.ts";

import { hasColumnAccess } from "../../config/app-access.ts";
import {
  APP_DELETED_AT_COLUMN,
  APP_RANK_COLUMN,
  appTableEventKinds,
  appTableVersions,
  AUTH_USERS,
} from "../../config/app-tables.ts";
import { CONFIG_DEFAULTS } from "../../config/defaults.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { moduleContext } from "../module-context.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  authenticatedPolicy,
  TENANT_SCOPE_NAMES,
  tenantScopePolicy,
} from "../tenant-scope.ts";
import {
  columnAccessChecks,
  columnAccessRefusals,
  readableColumns,
  writableColumns,
} from "./app-table-access.ts";
import { constraintChecks, sampleValue } from "./app-table-checks.ts";
import {
  enrichChecks,
  enrichSql,
  grantsPrelude,
  privilegeChecks,
  scopePolicyName,
} from "./app-table-enrich.ts";
import {
  checkSealBlocks,
  revealSql,
  sealChecks,
  sealSql,
} from "./app-table-seal.ts";
import { appTableSetSql, settableColumns } from "./app-table-set.ts";
import { appViewBehaviour, appViewChecks, appViewSql } from "./app-views.ts";
import { appTableSearchTriggers } from "./search.ts";
import { sessionPolicyTables } from "./sessions.ts";

/**
 * The `module` of the files `renderBlocks` writes for `appTables`. App tables
 * aren't a block: no `SQL_MODULES` entry, no preset, no row in
 * `better_supabase.blocks` (ADR 0040).
 */
export const APP_TABLES_MODULE = "app-tables";

/** The first line after the title of the app tables schema file. */
export const APP_TABLES_MARKER = "-- @bsb-tables";

const SCHEMA = "public";
const COMMANDS = ["select", "insert", "update", "delete"] as const;

/** A literal of each scope id type no tenant holds, for the RLS test. */
const FOREIGN_ID: Readonly<Record<BlockSqlIdType, string>> = {
  uuid: "gen_random_uuid()",
  text: "'bsb-app-tables-test'",
  bigint: "-1",
  integer: "-1",
};

interface ScopeColumn {
  readonly name: string;
  readonly definition: string;
  /** `definition` without `not null`, for a table that already has rows. */
  readonly addable: string;
  readonly idType: BlockSqlIdType;
}

interface AppTable {
  readonly name: string;
  readonly config: AppTableConfig;
  readonly ctx: BlockSqlContext;
  readonly scope: ScopeColumn | undefined;
  /** Whether `expose` sets the table's grants instead. */
  readonly exposed: boolean;
  /** Whether `blocks['sessions'].options.policies` adds `bsb_session_active`. */
  readonly sessionPolicy: boolean;
  /** The columns whose reference checks the tenant too, by column name. */
  readonly tenantReferences: ReadonlyMap<string, TenantReference>;
  /** Set when the app's own schema creates the table (`layout.ownTables`). */
  readonly enrich: EnrichTable | undefined;
}

/**
 * A reference between two tenant-scoped app tables. It becomes a foreign key on
 * `(tenant, column)` to the target's `(tenant, id)`, so a row can't point at a
 * row of another tenant.
 */
interface TenantReference {
  readonly column: string;
  readonly target: string;
  readonly tenant: string;
  readonly onDelete: AppReference["onDelete"];
}

const qualified = (table: string): string =>
  `${sqlIdent(SCHEMA)}.${sqlIdent(table)}`;

function scopeOf(table: AppTableConfig, layout: BlockSqlLayout): BlockScope {
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
  ctx: BlockSqlContext,
): ScopeColumn | undefined {
  switch (ctx.scope.kind) {
    case "tenant": {
      if (!ctx.installed("memberships")) {
        throw new TypeError(
          `tables.${name}: tenant scope needs the tenant block, which checks membership; add it to blocks, or set the table's owner to "user" or "none"`,
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
        addable: `${ctx.idType}${references}`,
        idType: ctx.idType,
      };
    }

    case "user": {
      const definition = `${ctx.scope.column()} references auth.users (id) on delete cascade`;

      return {
        name: "user_id",
        definition,
        addable: definition,
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
  ctx: BlockSqlContext,
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
  table: AppTable,
  name: string,
  column: AppColumnConfig,
): string {
  // Rows an enriched table already has stay valid: a column without a value
  // for them is added nullable.
  const notNull =
    column.nullable === false &&
    (table.enrich === undefined ||
      column.default !== undefined ||
      column.identity === true);

  return [
    `${sqlIdent(name)} ${column.encrypted === true ? "text" : (column.domain ?? column.type)}`,
    column.identity === true ? " generated by default as identity" : "",
    notNull ? " not null" : "",
    column.default === undefined ? "" : ` default ${column.default}`,
    column.unique === true ? " unique" : "",
    column.references === undefined || table.tenantReferences.has(name)
      ? ""
      : referenceSql(
          `tables.${table.name}.columns.${name}`,
          column.references,
          table.ctx,
        ),
  ].join("");
}

/**
 * The references of a tenant-scoped table to another tenant-scoped app table
 * (itself included), which `tenantKeysSql` checks per tenant.
 */
function tenantReferencesOf(
  table: Omit<AppTable, "tenantReferences">,
  tenantScoped: ReadonlySet<string>,
): ReadonlyMap<string, TenantReference> {
  const references = new Map<string, TenantReference>();

  if (table.ctx.scope.kind !== "tenant" || !table.scope) {
    return references;
  }

  for (const [column, config] of Object.entries(table.config.columns ?? {})) {
    const reference = config.references;

    if (
      reference !== undefined &&
      !("block" in reference) &&
      tenantScoped.has(reference.table)
    ) {
      references.set(column, {
        column,
        target: reference.table,
        tenant: table.scope.name,
        onDelete: reference.onDelete,
      });
    }
  }

  return references;
}

/**
 * The unique `(tenant, id)` index on every target of a tenant reference, then
 * each reference as a foreign key on `(tenant, column)`. The key is dropped and
 * added again so a re-run replaces the single-column key an earlier version
 * wrote under the same name. `set null` names the column (Postgres 15), so the
 * tenant column keeps its value.
 */
function tenantKeysSql(tables: readonly AppTable[]): string {
  const references = tables.flatMap((table) =>
    [...table.tenantReferences.values()].map((reference) => ({
      table: table.name,
      reference,
    })),
  );

  const targets = new Map(
    references.map(({ reference }) => [reference.target, reference.tenant]),
  );

  const indexes = [...targets].map(
    ([target, tenant]) =>
      `create unique index if not exists ${sqlIdent(`${target}_${tenant}_id_key`)} on ${qualified(target)} (${sqlIdent(tenant)}, id);`,
  );

  const keys = references.map(({ table, reference }) => {
    const name = sqlIdent(`${table}_${reference.column}_fkey`);
    const tenant = sqlIdent(reference.tenant);
    const column = sqlIdent(reference.column);

    const onDelete =
      reference.onDelete === undefined
        ? ""
        : reference.onDelete === "set null"
          ? ` on delete set null (${column})`
          : ` on delete ${reference.onDelete}`;

    return `alter table ${qualified(table)} drop constraint if exists ${name};
alter table ${qualified(table)} add constraint ${name} foreign key (${tenant}, ${column}) references ${qualified(reference.target)} (${tenant}, id)${onDelete};`;
  });

  return [...indexes, ...keys].join("\n");
}

function createSql(table: AppTable): string {
  if (table.enrich) {
    return enrichSql(table.enrich);
  }

  const timestamps = table.config.timestamps !== false;

  const columns = [
    table.config.id === "bigint"
      ? "id bigint generated by default as identity primary key"
      : "id uuid primary key default gen_random_uuid()",
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

/** The columns `subject.rank` and `subject.softDelete` add. */
function subjectColumnsSql(table: AppTable): readonly string[] {
  const subject = table.config.subject;

  return [
    ...(subject?.rank === undefined
      ? []
      : [`${sqlIdent(APP_RANK_COLUMN)} text collate "C" not null default 'V'`]),
    ...(subject?.softDelete === true
      ? [`${sqlIdent(APP_DELETED_AT_COLUMN)} timestamptz`]
      : []),
  ];
}

function columnsSql(table: AppTable): string {
  return [
    ...Object.entries(table.config.columns ?? {})
      .filter(([name]) => !table.enrich?.existing.has(name))
      .map(([name, column]) => columnSql(table, name, column)),
    ...subjectColumnsSql(table),
  ]
    .map(
      (column) =>
        `alter table ${qualified(table.name)} add column if not exists ${column};`,
    )
    .join("\n");
}

/** The rank key's index, within its group when the subject sets one. */
function rankIndex(table: AppTable): readonly (readonly string[])[] {
  const rank = table.config.subject?.rank;

  if (rank === undefined) {
    return [];
  }

  return [
    rank === true || rank.group === undefined
      ? [APP_RANK_COLUMN]
      : [rank.group, APP_RANK_COLUMN],
  ];
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

  return [
    ...indexed.map((column) => [column]),
    ...rankIndex(table),
    ...(table.config.indexes ?? []),
  ]
    .map(
      (columns) =>
        `create index if not exists ${sqlIdent(`${table.name}_${columns.join("_")}_idx`)} on ${qualified(table.name)} (${columns.map((column) => sqlIdent(column)).join(", ")});`,
    )
    .join("\n");
}

/** Every column of the table, implicit ones first. */
function columnNames(table: AppTable): readonly string[] {
  return [
    "id",
    ...(table.scope ? [table.scope.name] : []),
    ...(table.config.timestamps === false ? [] : ["created_at", "updated_at"]),
    ...Object.keys(table.config.columns ?? {}),
    ...(table.config.subject?.rank === undefined ? [] : [APP_RANK_COLUMN]),
    ...(table.config.subject?.softDelete === true
      ? [APP_DELETED_AT_COLUMN]
      : []),
  ];
}

/**
 * Throws when a composite `unique` or `indexes` key names a column the table
 * lacks.
 */
function checkKeyColumns(table: AppTable): void {
  const columns = new Set(columnNames(table));

  for (const key of ["unique", "indexes"] as const) {
    for (const set of table.config[key] ?? []) {
      const missing = set.find((column) => !columns.has(column));

      if (missing !== undefined) {
        throw new TypeError(
          `tables.${table.name}.${key}: the table has no column "${missing}" (${[...columns].join(", ")})`,
        );
      }
    }
  }
}

/**
 * The named check of each column and the composite unique keys, dropped and
 * added again so a re-run picks up an edited options list.
 */
function constraintsSql(table: AppTable): string {
  const target = qualified(table.name);

  const constraint = (name: string, body: string): string => {
    const ident = sqlIdent(name);

    return `alter table ${target} drop constraint if exists ${ident};
alter table ${target} add constraint ${ident} ${body};`;
  };

  return [
    ...Object.entries(table.config.columns ?? {}).flatMap(([name, column]) => {
      // The seal trigger checks an encrypted column before it encrypts it.
      const conditions =
        column.encrypted === true
          ? []
          : constraintChecks(column, sqlIdent(name));

      return conditions.length === 0
        ? []
        : [
            constraint(
              `${table.name}_${name}_check`,
              `check (${conditions.join(" and ")})`,
            ),
          ];
    }),
    ...(table.config.unique ?? []).map((columns) =>
      constraint(
        `${table.name}_${columns.join("_")}_key`,
        `unique (${columns.map((column) => sqlIdent(column)).join(", ")})`,
      ),
    ),
  ].join("\n");
}

function commentsSql(table: AppTable): string {
  const target = qualified(table.name);

  return [
    ...(table.config.comment === undefined
      ? []
      : [`comment on table ${target} is ${sqlString(table.config.comment)};`]),
    ...Object.entries(table.config.columns ?? {}).flatMap(([name, column]) =>
      column.comment === undefined
        ? []
        : [
            `comment on column ${target}.${sqlIdent(name)} is ${sqlString(column.comment)};`,
          ],
    ),
  ].join("\n");
}

/**
 * The rows a caller reaches: per tenant, rows of a tenant they are a member of;
 * per user, their own rows. `undefined` in `none` scope, where only the service
 * role writes.
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

  const policy = (
    command: (typeof COMMANDS)[number],
    spec: { using?: string; check?: string },
  ): string =>
    authenticatedPolicy(target, scopePolicyName(table, command), command, spec);

  if (own === undefined) {
    return policy("select", { using: table.ctx.scope.check("id", "null") });
  }

  return [
    policy("select", { using: own }),
    policy("insert", { check: own }),
    policy("update", { using: own, check: own }),
    policy("delete", { using: own }),
    ...(tenantScoped(table)
      ? [
          tenantScopePolicy({
            target,
            column: sqlIdent(table.scope.name),
            members: table.ctx.scope.members(),
            exempt: table.ctx.config.tenantScopeExempt,
          }),
        ]
      : []),
  ].join("\n");
}

/** A table whose rows belong to a tenant, kept apart by `bsb_tenant_scope`. */
function tenantScoped(
  table: AppTable,
): table is AppTable & { readonly scope: ScopeColumn } {
  return table.ctx.scope.kind === "tenant" && table.scope !== undefined;
}

function grantsSql(table: AppTable): string {
  const target = qualified(table.name);

  if (table.exposed) {
    if (hasColumnAccess(table.config)) {
      throw new TypeError(
        `tables.${table.name}: expose sets the grants, so its columns can't set access; drop access or the expose entry`,
      );
    }

    return `-- expose sets the grants on ${target}.`;
  }

  if (!hasColumnAccess(table.config)) {
    const privileges = table.scope
      ? "select, insert, update, delete"
      : "select";

    return `${grantsPrelude(target, table.enrich !== undefined)}
grant ${privileges} on ${target} to authenticated;
grant all on ${target} to service_role;`;
  }

  const list = (columns: readonly string[]): string =>
    columns.map((column) => sqlIdent(column)).join(", ");

  const readable = readableColumns(table.config, columnNames(table));
  const writable = writableColumns(table.config, columnNames(table));

  return [
    grantsPrelude(target, table.enrich !== undefined),
    `grant select (${list(readable)}) on ${target} to authenticated;`,
    ...(table.scope
      ? [
          `grant insert (${list(writable)}), update (${list(writable)}) on ${target} to authenticated;`,
          `grant delete on ${target} to authenticated;`,
        ]
      : []),
    `grant all on ${target} to service_role;`,
  ].join("\n");
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

/** The event type prefix: the subject type, or the table name. */
function eventBase(table: AppTable): string {
  return table.config.subject?.type ?? table.name;
}

/** The event kinds the table emits; empty without `events`. */
function eventKinds(table: AppTable): readonly AppTableEventKind[] {
  return appTableEventKinds(table.config);
}

/**
 * The trigger that writes `<base>.created`, `.updated` and `.deleted` to the
 * outbox (ADR 0048). An update that changes no column but `updated_at` emits
 * nothing.
 */
function eventsSql(table: AppTable): string {
  const kinds = eventKinds(table);

  if (kinds.length === 0) {
    return "";
  }

  const { ctx } = table;

  if (!ctx.installed("outbox")) {
    throw new TypeError(
      `tables.${table.name}.events needs the outbox block; add it to blocks`,
    );
  }

  const target = qualified(table.name);
  const fn = ctx.fn(`${table.name}_emit_event`);
  const trigger = ctx.trigger("emit_event");
  const base = eventBase(table);
  const events = table.config.events;

  const include =
    events === true || events === undefined ? [] : (events.include ?? []);

  const tenant = ctx.scope.kind === "tenant" ? table.scope?.name : undefined;
  const subject = table.config.subject;

  const fields = [
    `'id', v_row -> 'id'`,
    ...(tenant === undefined
      ? []
      : [`'organizationId', v_row -> ${sqlString(tenant)}`]),
    ...(subject === undefined
      ? []
      : [
          `'subjectType', ${sqlString(subject.type)}`,
          `'subjectId', v_row ->> 'id'`,
        ]),
    ...include.map(
      (column) => `${sqlString(column)}, v_row -> ${sqlString(column)}`,
    ),
  ];

  const emit = (kind: AppTableEventKind): string =>
    ctx.emit({
      type: `${base}.${kind}`,
      payload: `jsonb_build_object(${[...fields, ...(kind === "updated" ? ["'changed', to_jsonb(v_changed)"] : [])].join(", ")})`,
      subject: `${sqlString(`${table.name.replaceAll("_", "-")}/`)} || (v_row ->> 'id')`,
      ...(tenant === undefined
        ? {}
        : { tenant: `v_row ->> ${sqlString(tenant)}` }),
    });

  const branch = (kind: AppTableEventKind): string => {
    switch (kind) {
      case "created": {
        return `  if tg_op = 'INSERT' then
    v_row := to_jsonb(new);
    ${emit(kind)}
  end if;`;
      }

      case "updated": {
        return `  if tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    select coalesce(array_agg(n.key order by n.key), array[]::text[]) into v_changed
      from jsonb_each(v_row) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
     where n.value is distinct from o.value and n.key <> 'updated_at';
    if cardinality(v_changed) > 0 then
      ${emit(kind)}
    end if;
  end if;`;
      }

      case "deleted": {
        return `  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    ${emit(kind)}
  end if;`;
      }

      default: {
        const never: never = kind;

        throw new TypeError(`Unknown app table event "${String(never)}"`);
      }
    }
  };

  if (emit(kinds[0] ?? "created") === "") {
    return "";
  }

  const operations = kinds.map((kind) => TRIGGER_OPERATIONS[kind]).join(" or ");

  return `create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_changed text[];
begin
${kinds.map((kind) => branch(kind)).join("\n")}
  return null;
end;
$$;
revoke all on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${target};
create trigger ${trigger} after ${operations} on ${target}
  for each row execute function ${fn}();`;
}

/**
 * Whether `eventsSql` renders a trigger: the table sets `events` and the outbox
 * takes them.
 */
function emitsEvents(table: AppTable): boolean {
  const kind = eventKinds(table)[0];

  return (
    kind !== undefined &&
    table.ctx.installed("outbox") &&
    table.ctx.emit({ type: `${eventBase(table)}.${kind}`, payload: "null" }) !==
      ""
  );
}

/**
 * PgTAP checks, run as a signed-in user, that `app_table_set` refuses a column
 * it may not set.
 */
function setRefusals(table: AppTable): readonly string[] {
  const subject = table.config.subject;

  if (
    !table.ctx.installed("bulk") ||
    subject === undefined ||
    settableColumns(table.config).length === 0
  ) {
    return [];
  }

  const call = (values: string): string =>
    `$$select public.app_table_set(${FOREIGN_ID[table.ctx.idType]}, ${sqlString(subject.type)}, '1', '{"values": ${values}}'::jsonb)$$`;

  return [
    `select extensions.throws_ok(${call('{"id": "1"}')}, '22023', null, ${sqlString(`appTables.set refuses the id of ${SCHEMA}.${table.name}`)});`,
    `select extensions.throws_ok(${call("{}")}, '22023', null, ${sqlString(`appTables.set on ${SCHEMA}.${table.name} needs values`)});`,
  ];
}

/**
 * PgTAP checks for the auto snapshot trigger; `seeded` adds one for the seeded
 * row's version.
 */
function versionChecks(table: AppTable, seeded: boolean): readonly string[] {
  const subject = table.config.subject;
  const versions = appTableVersions(table.config);

  if (!subject || !versions?.auto || versions.columns.length === 0) {
    return [];
  }

  const trigger = table.ctx.trigger(`versions_${subject.type}_auto`);

  const checks = [
    `select extensions.has_trigger('${SCHEMA}'::name, ${sqlString(table.name)}::name, ${sqlString(trigger.replaceAll('"', ""))}::name, ${sqlString(`${SCHEMA}.${table.name} snapshots a version on each change`)});`,
  ];

  if (seeded) {
    const versions = table.ctx.of("versions");

    checks.push(
      `select extensions.ok(exists (select 1 from ${versions.table("versions")} v where v.${versions.col("versions", "subjectType")} = ${sqlString(subject.type)}), ${sqlString(`an insert into ${SCHEMA}.${table.name} snapshots a ${subject.type} version`)});`,
    );
  }

  return checks;
}

/**
 * PgTAP checks for the events trigger; `seeded` adds one that the seeded row
 * emitted.
 */
function eventChecks(table: AppTable, seeded: boolean): readonly string[] {
  if (!emitsEvents(table)) {
    return [];
  }

  const label = `${SCHEMA}.${table.name}`;

  const checks = [
    `select extensions.has_trigger('${SCHEMA}'::name, ${sqlString(table.name)}::name, ${sqlString(table.ctx.trigger("emit_event").replaceAll('"', ""))}::name, ${sqlString(`${label} emits outbox events`)});`,
  ];

  if (seeded && eventKinds(table).includes("created")) {
    const outbox = table.ctx.of("outbox");
    const type = `${eventBase(table)}.created`;

    checks.push(
      `select extensions.ok(exists (select 1 from ${outbox.table("events")} e where e.${outbox.col("events", "type")} = ${sqlString(type)}), ${sqlString(`an insert into ${label} emits ${type}`)});`,
    );
  }

  return checks;
}

const TRIGGER_OPERATIONS: Readonly<Record<AppTableEventKind, string>> = {
  created: "insert",
  updated: "update",
  deleted: "delete",
};

/** The table as the encryption SQL needs it. */
function sealTable(table: AppTable): SealTable {
  return {
    name: table.name,
    config: table.config,
    ctx: table.ctx,
    scope: table.scope,
    own: ownRows(table) ?? table.ctx.scope.check("id", "null"),
    sessionPolicy: table.sessionPolicy,
  };
}

function tableSql(table: AppTable): string {
  checkSealBlocks(sealTable(table));

  if (
    table.config.subject?.versions !== undefined &&
    !table.ctx.installed("versions")
  ) {
    throw new TypeError(
      `tables.${table.name}.subject.versions needs the versions block; add it to blocks`,
    );
  }

  return [
    `alter table ${qualified(table.name)} enable row level security;`,
    grantsSql(table),
    policiesSql(table),
    constraintsSql(table),
    indexesSql(table),
    commentsSql(table),
    triggerSql(table),
    eventsSql(table),
    sealSql(sealTable(table), constraintChecks),
    revealSql(sealTable(table)),
  ]
    .filter((part) => part !== "")
    .join("\n");
}

/**
 * Throws when an app table has the schema-qualified name of a table an
 * installed block keeps. The same bare name in another schema is allowed. A
 * table the app's own schema creates is enriched instead (`enrichSql`).
 */
function checkBlockTables(
  names: readonly string[],
  layout: BlockSqlLayout,
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
        const table = ctx.tableName(logical);
        taken.set(`${table.schema}.${table.name}`, module);
      }
    }
  }

  for (const name of names) {
    const qualified = `${SCHEMA}.${name}`;
    const module = taken.get(qualified);

    if (module !== undefined) {
      throw new TypeError(
        `tables.${name}: the ${module} block already keeps ${qualified}; choose another name`,
      );
    }
  }
}

function isExposed(name: string, layout: BlockSqlLayout): boolean {
  return (layout.grants ?? []).some(
    (grant) => grant.table === name || grant.table === `${SCHEMA}.${name}`,
  );
}

/**
 * The statement, run as the table owner before the role switch, that puts one
 * row of another tenant (or user) in the table, so the read check sees a row it
 * must not return. `undefined` when a required column has no stand-in value.
 */
function foreignRow(table: AppTable): string | undefined {
  const scope = table.scope;

  if (scope === undefined) {
    return undefined;
  }

  const values: [string, string][] = [];

  for (const [name, column] of Object.entries(table.config.columns ?? {})) {
    const value = sampleValue(column);

    if (value === undefined) {
      return undefined;
    }

    if (value !== null) {
      values.push([sqlIdent(name), value]);
    }
  }

  const { ctx } = table;
  const columns = [sqlIdent(scope.name), ...values.map(([name]) => name)];
  const rest = values.map(([, value]) => value);

  const insert = (owner: string): string =>
    `insert into ${qualified(table.name)} (${columns.join(", ")}) select ${[owner, ...rest].join(", ")}`;

  if (ctx.scope.kind === "user") {
    return `with u as (
  insert into auth.users (id, email, aud, role, instance_id)
  values (gen_random_uuid(), 'bsb-app-tables-' || gen_random_uuid()::text || '@example.test', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  returning id
)
${insert("u.id")} from u;`;
  }

  if (ctx.installed("organizations")) {
    const organizations = ctx.of("organizations");

    const org = (column: string): string =>
      organizations.col("organizations", column);

    const slug = organizations.has("organizations", "slug");

    return `with o as (
  insert into ${organizations.table("organizations")} (${org("name")}${slug ? `, ${org("slug")}` : ""})
  values ('bsb-app-tables-test'${slug ? ", 'bsb-app-tables-' || substr(md5(random()::text), 1, 8)" : ""})
  returning ${org("id")} as id
)
${insert("o.id")} from o;`;
  }

  return `${insert(FOREIGN_ID[scope.idType])};`;
}

function testSql(table: AppTable): string {
  const name = sqlString(table.name);
  const label = `${SCHEMA}.${table.name}`;
  const regclass = `${sqlString(qualified(table.name))}::regclass`;

  const policies = [
    ...(table.scope ? COMMANDS : (["select"] as const)).map((command) =>
      scopePolicyName(table, command),
    ),
    ...(table.sessionPolicy ? ["bsb_session_active"] : []),
    ...(tenantScoped(table) ? TENANT_SCOPE_NAMES : []),
  ];

  const policyList = policies.map((policy) => sqlString(policy)).join(", ");

  const checks = [
    `select extensions.has_table('${SCHEMA}', ${name}, ${sqlString(`${label} exists`)});`,
    `select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = ${regclass}), ${sqlString(`${label} has row level security on`)});`,
  ];

  checks.push(
    ...(table.enrich
      ? enrichChecks(table.enrich, policies)
      : [
          `select extensions.policies_are('${SCHEMA}', ${name}, array[${policyList}], ${sqlString(`${label} has the policies for its scope`)});`,
        ]),
  );

  for (const [column, config] of Object.entries(table.config.columns ?? {})) {
    if (
      config.encrypted !== true &&
      constraintChecks(config, sqlIdent(column)).length > 0
    ) {
      checks.push(
        `select extensions.col_has_check('${SCHEMA}'::name, ${name}::name, ${sqlString(column)}::name, ${sqlString(`${label}.${column} has its check`)});`,
      );
    }
  }

  for (const columns of table.config.unique ?? []) {
    checks.push(
      `select extensions.col_is_unique('${SCHEMA}'::name, ${name}::name, array[${columns.map((column) => sqlString(column)).join(", ")}]::name[], ${sqlString(`${label} is unique on ${columns.join(", ")}`)});`,
    );
  }

  for (const reference of table.tenantReferences.values()) {
    const constraint = sqlString(`${table.name}_${reference.column}_fkey`);

    checks.push(
      `select extensions.ok(exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = ${regclass} and k.conname = ${constraint} and k.contype = 'f' and cardinality(k.conkey) = 2), ${sqlString(`${label}.${reference.column} references a row of the same tenant`)});`,
    );
  }

  for (const columns of table.config.indexes ?? []) {
    checks.push(
      `select extensions.has_index('${SCHEMA}'::name, ${name}::name, ${sqlString(`${table.name}_${columns.join("_")}_idx`)}::name, ${sqlString(`${label} has an index on ${columns.join(", ")}`)});`,
    );
  }

  const access = {
    name: table.name,
    config: table.config,
    scoped: !!table.scope,
  };

  if (!table.exposed) {
    checks.push(...privilegeChecks(table), ...columnAccessChecks(access));
  }

  checks.push(...appViewChecks(table.name, table.config));

  // The test can't fill the required columns of the app's own table.
  const seeded = table.enrich === undefined ? foreignRow(table) : undefined;

  const sealed = sealChecks(
    sealTable(table),
    table.scope !== undefined && seeded !== undefined,
    sampleValue,
  );

  checks.push(...sealed.static);

  const widened = tenantScoped(table)
    ? " even through an app policy using (true)"
    : "";

  const readCheck =
    seeded === undefined
      ? `select extensions.skip(${sqlString(`${label} ${table.enrich ? "is the app's table" : "has a required reference"}, so the read test can't insert a row of another ${table.ctx.scope.kind}`)}, 1);`
      : `select extensions.is((select count(*)::integer from ${qualified(table.name)}), 0, ${sqlString(`a signed-in user does not read a row of ${label} outside their scope${widened}`)});`;

  const behaviour = table.scope
    ? [
        readCheck,
        `select extensions.throws_ok($$insert into ${qualified(table.name)} (${sqlIdent(table.scope.name)}) values (${FOREIGN_ID[table.scope.idType]})$$, '42501', null, ${sqlString(`a signed-in user cannot insert a row of ${label} outside their scope${widened}`)});`,
      ]
    : [
        `select extensions.throws_ok($$insert into ${qualified(table.name)} default values$$, '42501', null, ${sqlString(`a signed-in user cannot write ${label}; only the service role does`)});`,
      ];

  const seededSql = table.scope && seeded !== undefined ? seeded : undefined;

  const emitted = [
    ...eventChecks(table, seededSql !== undefined),
    ...versionChecks(table, seededSql !== undefined),
    ...sealed.seeded,
  ];

  return `${[...checks, ...(seededSql === undefined ? emitted : [])].join("\n")}
${seededSql === undefined ? "" : `\n${[seededSql, ...emitted].join("\n")}\n`}${tenantScoped(table) ? `\n-- An app's own permissive policy can't widen the tenant scope.\n${renderPolicy(makePolicy({ name: "bsb_test_app_widens", table: qualified(table.name), roles: ["authenticated"], using: "true", check: "true" }), { target: qualified(table.name) })}\n` : ""}
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
${[...behaviour, ...sealed.behaviour, ...setRefusals(table), ...appViewBehaviour(table.name, table.config, table.scope !== undefined), ...(table.exposed ? [] : columnAccessRefusals(access))].join("\n")}
reset role;`;
}

/**
 * The files for `layout.appTables`: one schema file that creates every app
 * table in `public` (implicit columns first, then each column with `add column
 * if not exists`, so a later column reaches an existing table), with row level
 * security, the grants and policies of its scope, indexes on the scope and
 * reference columns, and the `updated_at` trigger when the `updated-at` block
 * is installed; and one pgTAP file that checks the policies and grants. A table
 * the app's own schema already creates (`layout.ownTables`) is enriched: only
 * the columns it lacks are added, and the rest renders the same. Empty without
 * app tables. `installed` is every block module `renderBlocks` resolved.
 */
export function appTablesFiles(
  layout: BlockSqlLayout,
  installed: readonly string[],
): BlockSqlFile[] {
  const entries = Object.entries(layout.appTables ?? {});

  if (entries.length === 0) {
    return [];
  }

  checkBlockTables(
    entries.map(([name]) => name),
    layout,
    installed,
  );

  const scoped = entries.map(
    ([name, config]): Omit<AppTable, "tenantReferences"> => {
      const qualifiedName = `${SCHEMA}.${name}`;

      const ctx = moduleContext(
        APP_TABLES_MODULE,
        { ...layout, scope: scopeOf(config, layout) },
        installed,
      );

      const sessionTables = ctx.installed("sessions")
        ? sessionPolicyTables(ctx.of("sessions"), layout)
        : [];

      const scope = scopeColumn(name, ctx);
      const source = layout.ownTables?.[qualifiedName];

      return {
        name,
        config,
        ctx,
        scope,
        exposed: isExposed(name, layout),
        sessionPolicy: sessionTables.includes(qualifiedName),
        enrich:
          source === undefined
            ? undefined
            : {
                name,
                config,
                scope,
                source,
                existing: new Set(layout.ownColumns?.[qualifiedName]),
              },
      };
    },
  );

  const tenantScoped = new Set(
    scoped
      .filter((table) => table.ctx.scope.kind === "tenant" && table.scope)
      .map((table) => table.name),
  );

  const tables = scoped.map((table): AppTable => ({
    ...table,
    tenantReferences: tenantReferencesOf(table, tenantScoped),
  }));

  for (const table of tables) {
    checkKeyColumns(table);
  }

  const title = "-- better-supabase module: app-tables";

  const managed = [
    "-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.",
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
    tenantKeysSql(tables),
    tables
      .map((table) =>
        appViewSql(
          table.name,
          table.config,
          hasColumnAccess(table.config)
            ? readableColumns(table.config, columnNames(table))
            : undefined,
        ),
      )
      .filter((part) => part !== "")
      .join("\n\n"),
    installed.includes("search")
      ? appTableSearchTriggers(moduleContext("search", layout, installed))
      : "",
    installed.includes("bulk") && tables[0]
      ? appTableSetSql(
          tables.map((table) => ({
            name: table.name,
            config: table.config,
            tenant:
              table.ctx.scope.kind === "tenant" ? table.scope?.name : undefined,
          })),
          tables[0].ctx.idType,
        )
      : "",
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
      contents: `${title}\n-- @bsb-block-test ${APP_TABLES_MODULE}\n${managed.join("\n")}\n\nbegin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(${String(plan)});

${tables.map((table) => testSql(table)).join("\n\n")}

select * from extensions.finish();
rollback;\n`,
    },
  ];
}
