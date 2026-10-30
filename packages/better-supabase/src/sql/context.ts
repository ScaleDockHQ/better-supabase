import type {
  BlockMode,
  AnyBlocksConfig,
  BlockScope,
  InstanceOn,
  ResolvedBlock,
} from "../config/blocks.ts";
import type { ResolvedInstance } from "../config/instances.ts";
import type { SubjectsConfig } from "../config/types/subjects.ts";
import type { DefaultAutomation } from "../core/automation.ts";
import type { BlockEventType, EventMap } from "../core/block-events.ts";
import type { EntityNames } from "../core/entity-naming.ts";
import type { ClaimsMeta } from "../schema/types.ts";
import type { BlockContributions } from "./contributions.ts";
import type { BlockSqlAppTable, OwnView } from "./module-types.ts";
import type { ResolvedNames } from "./resolved-names.ts";
import type { BlockSqlScope } from "./scope.ts";
import type { BlockSqlValueMethods } from "./value-maps.ts";

import { optionSchemaOf } from "../blocks/options-registry.ts";
import { resolveBlock } from "../config/blocks.ts";
import { instancePrefix } from "../config/instances.ts";
import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { composeNames } from "../core/entity-naming.ts";
import { sqlIdent, sqlString } from "../core/template.ts";
import { tableOwnership } from "./app-owned.ts";
import { defaultRuleRow, shipsEnabled } from "./default-rule-row.ts";
import { checkedExtraColumns } from "./extra-columns.ts";
import {
  checkInstanceEntities,
  instanceArea,
  instanceEntityNames,
} from "./instance-area.ts";
import { resolveNames } from "./resolved-names.ts";
import { moduleScope } from "./scope.ts";
import { NOTHING, SERVICE_CALLER } from "./shared.ts";
import { logsSubjectReads } from "./subject-registry.ts";
import { blockColumnName } from "./tenant-column.ts";
import { checkedValueMaps, valueMethods } from "./value-maps.ts";

export { NOTHING };

/** The scope id types SQL modules render. */
export const MODULE_ID_TYPES = ["uuid", "text", "bigint", "integer"] as const;

export type BlockSqlIdType = (typeof MODULE_ID_TYPES)[number];

export const isBlockSqlIdType = (value: string): value is BlockSqlIdType =>
  MODULE_ID_TYPES.some((type) => type === value);

const ID_TYPE_ALIASES: Readonly<Record<string, BlockSqlIdType>> = {
  int8: "bigint",
  int4: "integer",
  int: "integer",
  varchar: "text",
  "character varying": "text",
};

/**
 * A Postgres type name as one of `MODULE_ID_TYPES`: case and spacing are
 * normalised and aliases such as `int8` resolved. `undefined` for any other
 * type, so callers refuse it instead of guessing.
 */
export function moduleIdType(value: string): BlockSqlIdType | undefined {
  const name = value.trim().toLowerCase().replaceAll(/\s+/g, " ");

  return isBlockSqlIdType(name) ? name : ID_TYPE_ALIASES[name];
}

/** One logical table of a module: its default name and logical columns. */
export interface BlockSqlTableSpec {
  /** Default name, in the module's schema. */
  readonly name: string;
  /** Logical column to default column name. */
  readonly columns: Readonly<Record<string, string>>;
  /**
   * Logical columns an adopted table may lack (mapped to `null`): the module
   * leaves out the feature that needs them.
   */
  readonly optional?: readonly string[];
  /** The app may lack the whole table (`blocks.<name>.tables.<table>: null`). */
  readonly optionalTable?: boolean;
  /**
   * How the table can be a table the app already has (ADR 0098). Without it the
   * module always creates the table.
   */
  readonly app?: BlockSqlAppTable;
  readonly lifecycle?: BlockSqlTableLifecycle;
  /**
   * Text columns an adopted table may declare with another type, such as an
   * enum: the module writes and compares them through `ctx.cast`.
   */
  readonly typed?: readonly string[];
  /**
   * Text columns that take `blocks.<name>.values` like `typed` ones, but are
   * written through `ctx.cast` only when the app gives them a values entry (an
   * empty one casts without renaming labels), so a config without one renders
   * as before.
   */
  readonly mappable?: readonly string[];
  readonly yieldsToExtra?: readonly string[];
}

export interface BlockSqlTableLifecycle {
  readonly user?: string;
  readonly tenant?: string;
  readonly purge?: boolean;
  readonly omit?: readonly string[];
  readonly export?: boolean;
  /**
   * Columns that hold a `credential_ref`. Exports leave them out, and the
   * organization purger revokes each ref that carries the row's tenant through
   * the `CredentialProvider` before the purge deletes the row.
   */
  readonly credentials?: readonly string[];
  /** Revoke for the row's `user` instead of the app. Default `app`. */
  readonly credentialSubject?: "app" | "user";
}

/**
 * What makes an entity a `config.subjects` entry when the block is installed.
 * Columns are the table's logical columns; permissions are module actions.
 */
export interface BlockSqlEntitySubject {
  readonly title: string;
  readonly fallbackTitle?: string;
  readonly deletedAt?: string;
  readonly permissions: {
    readonly read: string;
    readonly write: string;
    /**
     * The action whose key `attachments` checks for files on the entity, in
     * place of `attachments.upload`. Set it when the table's own write policies
     * check more than tenant membership (doctor BS345).
     */
    readonly upload?: string;
  };
  readonly rank?: { readonly column: string; readonly group: string };
  readonly search?: {
    readonly title: string;
    readonly body: readonly string[];
  };
  readonly url?: string;
  readonly cascade?: boolean;
}

/**
 * A noun the module names its tables, functions, events, permissions and hooks
 * after (`work_item`), renamed through `blocks.<name>.entities`.
 */
export interface BlockSqlEntitySpec {
  /** The logical table that holds the entity; global entities may have none. */
  readonly table?: string;
  readonly singular: string;
  /** Defaults to the English plural of `singular`. */
  readonly plural?: string;
  /**
   * The singular before 0.47 (`work_item` for `task`); tables and events keep
   * it.
   */
  readonly formerly?: string;
  /** The entity `entities: "<noun>"` renames. */
  readonly primary?: boolean;
  /** Renamed in every module, not only this one (the tenant). */
  readonly global?: boolean;
  readonly subject?: BlockSqlEntitySubject;
}

export interface BlockSqlNames {
  readonly tables: Readonly<Record<string, BlockSqlTableSpec>>;
  readonly entities?: Readonly<Record<string, BlockSqlEntitySpec>>;
  /**
   * The `before_*` and `after_*` hooks the module calls, so
   * `blocks.<name>.hooks.functions` is checked.
   */
  readonly hooks?: readonly string[];
  /**
   * The `blocks.<name>.options` keys the module reads; any other key is
   * rejected.
   */
  readonly options?: readonly string[];
  /**
   * The events the module records, typed against its block's event map
   * (`BlockSqlEvents<MessagingEvents>`); `record` rejects any other type.
   */
  readonly events?: Readonly<Record<string, CheckedEventSpec | undefined>>;
  /**
   * Tables and columns the module renamed between versions. `upgrade` renames
   * them on installs below `from + 1`, after the config's entity and table
   * renames, so a declared move needs no hand-written upgrade step.
   */
  readonly migrations?: readonly BlockSqlNameMigration[];
}

/**
 * One version's table and column moves. Old names are the module's default
 * names before the move; they go through the entity renames like every other
 * name.
 */
export interface BlockSqlNameMigration {
  /** The installed version this move upgrades from. */
  readonly from: number;
  readonly description: string;
  /** The logical table, under its current key. */
  readonly table: string;
  /** The table's default name before the move, when the move renamed it. */
  readonly was?: string;
  /** Logical column to its default name before the move. */
  readonly columns?: Readonly<Record<string, string>>;
}

/** An event in a module's catalog, checked against what `record` renders. */
export interface BlockSqlEventSpec<
  M extends EventMap = EventMap,
  K extends BlockEventType<M> = BlockEventType<M>,
> {
  /** The kebab-case collection every subject starts with, e.g. `organizations`. */
  readonly subject: string;
  /** The payload keys, all of them in the event's data in the block's event map. */
  readonly payload: readonly PayloadKey<M, K>[];
  /**
   * A job, a webhook or an engine may call the writer again, so the event needs
   * a `key`.
   */
  readonly retries?: boolean;
}

type PayloadKey<M extends EventMap, K extends BlockEventType<M>> =
  K extends BlockEventType<M> ? keyof M[K] & string : never;

/** The events a module records, typed by its block's event map `M`. */
export type BlockSqlEvents<M extends EventMap = EventMap> = {
  readonly [K in BlockEventType<M>]?: BlockSqlEventSpec<M, K>;
};

interface CheckedEventSpec {
  readonly subject: string;
  readonly payload: readonly string[];
  readonly retries?: boolean;
}

const SUBJECT_COLLECTION = /^[a-z]+(-[a-z]+)*s$/;

/** An event a module writes to the outbox, as SQL expressions. */
export interface BlockSqlEmit {
  /** The event type, e.g. `organization.created`. */
  readonly type: string;
  /** A `jsonb` expression. */
  readonly payload: string;
  /** A `text` expression, e.g. `'organizations/' || new_organization`. */
  readonly subject?: string;
  /** The tenant id expression; it is cast to text. */
  readonly tenant?: string;
  /** A `text` idempotency key expression. */
  readonly key?: string;
}

/**
 * The categories module actions are audited under. An adopted log with its own
 * names maps them through `blocks.audit.options.values.category`.
 */
export const AUDIT_CATEGORIES = [
  "membership",
  "access",
  "security",
  "configuration",
  "billing",
  "data",
  "ai",
  "integration",
  "read",
] as const;

export type AuditCategory = (typeof AUDIT_CATEGORIES)[number];

/** How `record` writes an action to the audit log, as SQL expressions. */
export interface BlockSqlAudit {
  /** The audit category, mapped through `blocks.audit.options.values`. */
  readonly category: AuditCategory;
  /** What the action changed, e.g. `user` or `api_key`. */
  readonly targetType?: string;
  /** A `text` expression for the changed record's id. */
  readonly recordId?: string;
  /** A `text` expression people recognize the target by. */
  readonly targetLabel?: string;
  /** A `text` expression that says what happened. */
  readonly summary?: string;
  /** A `jsonb` expression; defaults to the event payload. */
  readonly metadata?: string;
  /** A `uuid` expression for the actor; defaults to the caller. */
  readonly actor?: string;
  /**
   * A `uuid` expression for the support session the action belongs to. Defaults
   * to the session in the caller's `act` claim, which wins when set.
   */
  readonly supportSession?: string;
  /**
   * A `uuid` expression for the admin acting as the user; defaults to
   * `act.sub`.
   */
  readonly impersonatedBy?: string;
  /**
   * A `text` expression for why the admin acts as the user; defaults to
   * `act.reason`.
   */
  readonly impersonationReason?: string;
}

/**
 * An action a module records once: the outbox gets it as an event and the audit
 * log as an entry, each when its module is installed.
 */
export interface BlockSqlAction extends BlockSqlEmit {
  /**
   * How the action is audited, or `false` for an event that is not an audited
   * action, such as a chat message or a run status.
   */
  readonly audit: BlockSqlAudit | false;
}

const TENANT_PROVIDERS: ReadonlySet<string> = new Set([
  "memberships",
  "permissions",
]);

// These modules write their functions into better_supabase whatever
// blocks.<name>.schema says; the schema only places their tables.
const FIXED_FUNCTION_MODULES: ReadonlySet<string> = new Set([
  "permissions",
  "queue",
  "webhook-inbox",
]);

// The tenant module's role helpers stay in better_supabase whatever its
// schema says: policies, doctor and app SQL name them there. fn() returns
// them unquoted, as the tenant module defines them, so callers render the
// same text as the definitions.
const FIXED_FUNCTIONS: Readonly<Record<string, ReadonlySet<string>>> = {
  memberships: new Set([
    "member_organization_ids",
    "has_organization_role",
    "organization_member_role",
    "organization_member_roles",
  ]),
};

/**
 * A function of a module's contract: what other modules and the TypeScript side
 * call.
 */
export interface BlockSqlContractFunction {
  readonly name: string;
  /** Argument types; `{id}` stands for the module's id type. */
  readonly args: readonly string[];
  readonly returns: string;
}

/** What a module's `build` reads: resolved names for one layout. */
export interface BlockSqlContext extends BlockSqlValueMethods {
  readonly module: string;
  /**
   * The instance being rendered: the module's name, or the `blocks` key of an
   * instance that installs the module under another name.
   */
  readonly instance: string;
  /**
   * `blocks.<instance>.on`: the record types the instance attaches to, as a
   * list or keyed by type with settings. Unset, it attaches to every one.
   */
  readonly on: InstanceOn | undefined;
  readonly mode: BlockMode;
  readonly config: ResolvedBlock;
  /** The quoted schema of the module's functions and managed tables. */
  readonly schema: string;
  readonly schemaName: string;
  readonly idType: BlockSqlIdType;
  readonly claims: ClaimsMeta;
  readonly modules: AnyBlocksConfig;
  /** The app-wide subject registry (`config.subjects`). */
  readonly subjects: SubjectsConfig;
  /** The provider's `rowsWith` and `rowsWithFor` templates under `provider`. */
  readonly providerRowsWith: string | undefined;
  readonly providerRowsWithFor: string | undefined;
  /**
   * The names of `config.appTables`, created in `public` after every block
   * file, so a block can't put a trigger on one (ADR 0043).
   */
  readonly appTables: ReadonlySet<string>;
  /**
   * Who the module's rows belong to, and the checks for it: the port every
   * tenant, user or shared-space check goes through.
   */
  readonly scope: BlockSqlScope;
  /**
   * The module's final names: its entities as `blocks.<name>.entities` and
   * `blocks.memberships.names.organization` rename them.
   */
  readonly resolved: ResolvedNames;
  /** The renamer every default name goes through (`resolved.naming`). */
  readonly naming: EntityNames;
  /**
   * Every configured block's entity renames as one, for names that span blocks,
   * such as the permission keys in the default roles.
   */
  blockNaming(): EntityNames;
  /**
   * The entity renames of each block installed under another name, such as
   * `tickets` from `tasks`, for the permission keys each instance adds.
   */
  instanceNamings(): readonly EntityNames[];
  /**
   * What the installed instances whose `uses` names this instance add to it
   * through `contributes`, in block order. Custom-mode instances add nothing.
   */
  contributions<K extends keyof BlockContributions>(
    block: K,
  ): readonly BlockContributions[K][];
  /**
   * `schema.name` of a module function, quoted. The name is the default one;
   * `blocks.<name>.entities` and `blocks.<name>.functions` rename it.
   */
  fn(name: string): string;
  /** The unquoted name a module function is written under (see `fn`). */
  fnName(name: string): string;
  /** `blocks.<name>.functions` keys no `fn` call has asked for yet. */
  unusedFunctions(): readonly string[];
  /** Default name to written name, for every function `fn` renamed so far. */
  functionRenames(): ReadonlyMap<string, string>;
  /** `schema.table` of a logical table, quoted. */
  table(logical: string): string;
  /** The unquoted schema and name of a logical table. */
  tableName(logical: string): {
    readonly schema: string;
    readonly name: string;
  };
  /** A logical column, quoted. Throws when an adopted table lacks it. */
  col(table: string, column: string): string;
  /** A logical column, unquoted. Throws when an adopted table lacks it. */
  colName(table: string, column: string): string;
  /** Whether a logical column exists (adopted tables can map it to `null`). */
  has(table: string, column: string): boolean;
  /** Whether an optional logical table exists (it can be mapped to `null`). */
  hasTable(table: string): boolean;
  /** Whether the module renders its managed SQL (not adopt or custom mode). */
  readonly manages: boolean;
  /** Whether the module creates `table`, which the app doesn't have. */
  owns(table: string): boolean;
  /** The logical tables the app has; the module only adds their columns. */
  readonly appOwned: readonly string[];
  /**
   * The entries of `appOwned` that are views: the module writes no DDL on them,
   * only the functions that read them.
   */
  readonly appViews: readonly string[];
  readonly names: BlockSqlNames;
  readonly installedModules: readonly string[];
  /** The permission key for a module action, as a SQL literal. */
  permission(action: string, fallback: string): string;
  /** The permission key for a module action. */
  permissionKey(action: string, fallback: string): string;
  /** A trigger name with the module's prefix, quoted. */
  trigger(name: string): string;
  /** Whether `module` is installed alongside this one. */
  installed(module: string): boolean;
  /** The context of another module in the same layout. */
  of(module: string): BlockSqlContext;
  /** A string module option (`blocks.<name>.options`). */
  text(name: string, fallback: string): string;
  number(name: string, fallback: number): number;
  flag(name: string, fallback: boolean): boolean;
  /** A module option that is a list of strings. */
  list(name: string, fallback: readonly string[]): readonly string[];
  /** A declared module option as configured, for object-shaped options. */
  option(name: string): unknown;
  /**
   * `options.extraColumns` (column name to SQL type), checked: names are
   * lower-case identifiers, types are SQL types, and no name shadows one of
   * `table`'s mapped columns or a key in `reserved`, the stable keys the
   * module's read functions return next to them.
   */
  extraColumns(
    table: string,
    reserved?: readonly string[],
    name?: string,
  ): readonly ExtraColumn[];
  /**
   * PL/pgSQL that calls the app's hook function when it exists, with `[type,
   * expression]` arguments: `if to_regprocedure(...) is not null then execute
   * format(...) using ...; end if;`. The name comes from `to_regprocedure`
   * rather than a literal: plpgsql_check (`supabase db lint`) checks constant
   * dynamic SQL and fails when the hook is missing.
   */
  hook(name: string, args: readonly (readonly [string, string])[]): string;
  /** The app function a hook calls, quoted, for hooks that return a value. */
  hookTarget(name: string): string;
  /**
   * PL/pgSQL that writes the event to the outbox (`emit_event`) when the
   * `outbox` module is installed and `blocks.<name>.events` isn't false;
   * otherwise an empty string. `record` without the audit entry.
   */
  emit(event: BlockSqlEmit): string;
  /**
   * PL/pgSQL that writes the action to the outbox (as `emit` does) and, when it
   * carries `audit` and the `audit` module is installed, to the audit log
   * (`audit_event`), with `key` as the idempotency key of both. `null;` when
   * neither applies, so it is always a valid statement.
   */
  record(action: BlockSqlAction): string;
  /**
   * PL/pgSQL that writes the action to the audit log only, with no outbox
   * event, for reads that leave no change behind. `null;` without the `audit`
   * module or when `audit` is `false`.
   */
  audit(action: BlockSqlAction): string;
  /**
   * PL/pgSQL that logs a read of record `subjectId` of type `subjectType` (SQL
   * `text`) by function `fnName` through `record_subject_read`. Empty unless
   * `audit` and `subjects` are installed and some type has `auditReads`.
   */
  read(subjectType: string, subjectId: string, fnName: string): string;
  /** `volatile` when `read` renders a call, which writes, else `stable`. */
  readVolatility(): "stable" | "volatile";
  /**
   * PL/pgSQL that calls `notify(fields)` as the service role, which `notify()`
   * requires, then restores the caller's claims. The function declares
   * `v_claims text`. `null;` without the `notifications` module.
   */
  notify(fields: string, options?: { readonly indent?: string }): string;
  /**
   * PL/pgSQL that enqueues a job (`enqueue_job`); `null;` without the `jobs`
   * module. `delay` is an integer expression of seconds before it runs.
   */
  enqueue(
    queue: string,
    payload: string,
    dedupe: string,
    options?: { readonly delay?: string },
  ): string;
  /**
   * Row SQL for `data` that ships an automation as a default rule
   * (`rule_defaults`): every organization gets its own copy, which it may turn
   * off or edit. The trigger and subject type follow the module's entity
   * renames. `''` without the `automations` module or a block in `requires`.
   */
  automation(spec: DefaultAutomation): string;
  /**
   * The `text[]` of a tenant's entitlements, or `fallback` without the
   * `entitlements` module.
   */
  entitlements(tenant: string): string | undefined;
  entitlements(tenant: string, fallback: string): string;
  /**
   * How long rows of `kind` are kept for `tenant` (SQL expressions): the
   * data-lifecycle policy for the tenant, its plan or every tenant, else
   * `fallback`; just `fallback` without the `data-lifecycle` module.
   */
  retention(kind: string, tenant: string, fallback: string): string;
  /**
   * Whether a legal hold covers `kind` for `tenant`; `false` without the
   * `data-lifecycle` module.
   */
  held(kind: string, tenant: string): string;
  /**
   * The condition a purge deletes on: the row's timestamp `at` is past
   * `retention` and no hold covers it. With data-lifecycle it first bounds `at`
   * by the shortest policy, so the timestamp index still serves.
   */
  expired(
    kind: string,
    row: {
      readonly at: string;
      readonly tenant: string;
      readonly fallback: string;
    },
  ): string;
  /**
   * Before when every tenant's rows of `kind` may go (a timestamptz
   * expression), for dropping whole partitions: null under any hold on the
   * kind, else the longest policy or `fallback`; `now() - fallback` without the
   * `data-lifecycle` module.
   */
  cutoff(kind: string, fallback: string): string;
  /**
   * PL/pgSQL that broadcasts on a Realtime topic when `realtime.send` exists:
   * projects without Realtime skip it.
   */
  broadcast(
    topic: string,
    event: string,
    payload: string,
    options?: { readonly indent?: string },
  ): string;
  /**
   * `coalesce(better_supabase.can(scope, id, permission), false)`; `permission`
   * is a SQL expression. The `tenant` scope goes through `scope.can`.
   */
  can(scope: string, id: string, permission: string): string;
  /**
   * True for the service role and platform staff holding `permission` (a SQL
   * expression); the service role only without the `access` module.
   */
  staff(permission: string): string;
}

/** A column from `options.extraColumns`. */
export interface ExtraColumn {
  /** The column name, as reads return it. */
  readonly name: string;
  /** The name, quoted. */
  readonly ident: string;
  /** Its SQL type, such as `text not null default 'en'`. */
  readonly type: string;
}

export interface BlockSqlContextSource {
  readonly modules?: AnyBlocksConfig;
  /** `config.subjects`, which `subjectsOption` falls back to. */
  readonly subjects?: SubjectsConfig;
  /** The names of `config.appTables`. */
  readonly appTables?: readonly string[];
  readonly claims?: ClaimsMeta;
  /** The modules being installed together. */
  readonly installed?: readonly string[];
  /** The id type the authorization provider gives, when the layout has one. */
  readonly providerIdType?: BlockSqlIdType;
  /**
   * Whether the authorization provider answers for guests
   * (`functions.portalSubjects` or `portalParties`) under the `provider`
   * model.
   */
  readonly providerGuests?: boolean;
  /** The provider's `functions.rowsWith` and `rowsWithFor` templates. */
  readonly providerRowsWith?: string;
  readonly providerRowsWithFor?: string;
  /** `sql.scope`: the scope of a module whose config sets none. */
  readonly scope?: BlockScope;
  readonly tenantColumn?: string;
  /**
   * The modules `module` may read through `installed` and `of`: what it
   * requires and what it lists in `integrates`. Without it nothing is checked.
   */
  readonly integrations?: (module: string) => ReadonlySet<string> | undefined;
  /** `config.instances`: what `of` follows through each instance's `uses`. */
  readonly instances?: Readonly<Record<string, ResolvedInstance>>;
  /**
   * The instance to render when it installs the module under another name. Its
   * names get the instance's prefix where its entity renames leave them
   * unchanged.
   */
  readonly instance?: string;
  /**
   * The installed instances that contribute to `block`, each with the instance
   * of `block` its `uses` names.
   */
  readonly contributors?: <K extends keyof BlockContributions>(
    block: K,
  ) => readonly Contributor<K>[];
  /** `layout.ownTables`: the app's tables, as `schema.table`. */
  readonly ownTables?: Readonly<Record<string, string>>;
  /** `layout.ownViews`: the entries of `ownTables` that are views. */
  readonly ownViews?: Readonly<Record<string, OwnView>>;
}

/** An installed instance that adds to a generic block. */
export interface Contributor<K extends keyof BlockContributions> {
  /** The instance of the generic block it adds to. */
  readonly instance: string;
  readonly contribute: (
    target: BlockSqlContext,
  ) => readonly BlockContributions[K][];
}

const IDENT = /^[A-Za-z_][A-Za-z0-9_$]*$/;

function splitTable(
  value: string,
  schema: string,
): { readonly schema: string; readonly name: string } {
  const dot = value.indexOf(".");

  return dot === -1
    ? { schema, name: value }
    : { schema: value.slice(0, dot), name: value.slice(dot + 1) };
}

function checkIdent(where: string, value: string): string {
  if (!IDENT.test(value) || value.length > 63) {
    throw new TypeError(`${where}: "${value}" is not a valid identifier`);
  }

  return value;
}

/**
 * Builds the context for `module`. `namesOf` looks up a module's names, so a
 * module can name another module's tables through `of()`.
 */
export function createModuleContext(
  module: string,
  namesOf: (name: string) => BlockSqlNames | undefined,
  source: BlockSqlContextSource = {},
): BlockSqlContext {
  const { instance: own, ...shared } = source;
  const instance = own ?? module;
  const entry = source.instances?.[instance];
  const prefix = instance === module ? undefined : instancePrefix(instance);

  const modules =
    prefix === undefined
      ? (source.modules ?? {})
      : { ...source.modules, [module]: entry?.config ?? {} };

  const config = resolveBlock(modules[module]);
  const where = `blocks.${instance}`;
  const names = namesOf(module) ?? { tables: {} };
  checkIdent(`${where}.schema`, config.schema);

  for (const [table, name] of Object.entries(config.tables)) {
    const known = names.tables[table];

    if (!known) {
      throw new TypeError(
        `${where}.tables: unknown table "${table}". Tables: ${Object.keys(names.tables).join(", ") || "none"}`,
      );
    }

    if (name === null && !known.optionalTable) {
      throw new TypeError(
        `${where}.tables.${table} is required and can't be null`,
      );
    }
  }

  for (const [table, columns] of Object.entries(config.columns)) {
    const known = names.tables[table];

    if (!known) {
      throw new TypeError(
        `${where}.columns: unknown table "${table}". Tables: ${Object.keys(names.tables).join(", ") || "none"}`,
      );
    }

    for (const [column, name] of Object.entries(columns)) {
      if (!(column in known.columns)) {
        throw new TypeError(
          `${where}.columns.${table}: unknown column "${column}". Columns: ${Object.keys(known.columns).join(", ")}`,
        );
      }

      if (name === null) {
        if (!known.optional?.includes(column)) {
          throw new TypeError(
            `${where}.columns.${table}.${column} is required and can't be null`,
          );
        }
      } else {
        checkIdent(`${where}.columns.${table}.${column}`, name);
      }
    }
  }

  checkIdent(`${where}.hooks.schema`, config.hooks.schema);

  for (const [hook, target] of Object.entries(config.hooks.functions)) {
    if (!names.hooks?.includes(hook)) {
      throw new TypeError(
        `${where}.hooks.functions: unknown hook "${hook}". Hooks: ${names.hooks?.length ? names.hooks.join(", ") : "none"}`,
      );
    }

    const parts = splitTable(target, config.hooks.schema);
    checkIdent(`${where}.hooks.functions.${hook}`, parts.schema);
    checkIdent(`${where}.hooks.functions.${hook}`, parts.name);
  }

  const declared = new Set(names.options);

  for (const key of Object.keys(config.options)) {
    if (key === "subjects") {
      throw new TypeError(
        `${where}.options.subjects moved to ${where}.on. Run \`better-supabase upgrade\` to move it.`,
      );
    }

    if (!declared.has(key)) {
      throw new TypeError(
        `${where}.options: unknown option "${key}". Options: ${[...declared].join(", ") || "none"}`,
      );
    }
  }

  const optionsSchema = optionSchemaOf(module);

  if (optionsSchema !== undefined) {
    const outcome = optionsSchema["~standard"].validate(config.options);

    if (!(outcome instanceof Promise) && outcome.issues !== undefined) {
      const [issue] = outcome.issues;
      throw new TypeError(
        `${where}.options: ${issue?.message ?? "invalid options"}`,
      );
    }
  }

  const option = (name: string): unknown => {
    if (!declared.has(name)) {
      throw new TypeError(
        `Module "${module}" reads option "${name}", which its names.options doesn't declare`,
      );
    }

    return config.options[name];
  };

  // The tenant module and the access contract are what tenant scope runs
  // on, so they render for tenants whatever scope the blocks around them use.
  const scopeKind = TENANT_PROVIDERS.has(module)
    ? "tenant"
    : (config.scope ?? source.scope ?? "tenant");

  const rawId =
    scopeKind === "user"
      ? (config.idType ?? "uuid")
      : (config.idType ??
        modules.permissions?.idType ??
        source.providerIdType ??
        "uuid");

  const idType = moduleIdType(rawId);

  if (!idType) {
    throw new TypeError(
      `${where}.idType: "${rawId}" is not one of ${MODULE_ID_TYPES.join(", ")}`,
    );
  }

  if (scopeKind === "user" && idType !== "uuid") {
    throw new TypeError(
      `${where}.idType: in user scope the scope id is a user id, so it is uuid, not ${idType}`,
    );
  }

  const resolved = resolveNames(module, names, modules);
  const { naming, entityNaming } = resolved;

  if (prefix !== undefined) {
    checkInstanceEntities(instance, module, names, resolved, source.instances);
  }

  // A name the instance's entity renames leave unchanged would clash with
  // the module's other instances, so it takes the instance's prefix.
  const legacy = (name: string): string => resolved.functionNouns.rename(name);

  const scoped = (written: string, original: string): string =>
    prefix === undefined ||
    entityNaming.rename(legacy(original)) !== legacy(original)
      ? written
      : `${prefix}_${written}`;

  const ownKey = (key: string): string =>
    instanceArea(
      module,
      prefix === undefined ? undefined : instance,
      entityNaming.rename(key),
    );

  // blocks.permissions.functions holds the custom model's templates, and the
  // access contract's names (can, tenant_ids_with) name no tenant.
  const renames = module === "permissions" ? {} : config.functions;

  for (const [name, target] of Object.entries(renames)) {
    checkIdent(`${where}.functions`, name);
    checkIdent(`${where}.functions.${name}`, target);
  }

  const requested = new Set<string>();
  const applied = new Map<string, string>();

  const fnName = (name: string): string => {
    const renamed = naming.rename(legacy(name));
    requested.add(name).add(renamed).add(resolved.formerName(name));

    const written =
      renames[name] ??
      renames[resolved.formerName(name)] ??
      renames[renamed] ??
      scoped(renamed, name);

    if (written !== name) {
      applied.set(name, written);
    }

    return written;
  };

  const tableName = (logical: string) => {
    const table = names.tables[logical];

    if (!table) {
      throw new TypeError(`Module "${module}" has no table "${logical}"`);
    }

    const mapped = config.tables[logical];

    if (mapped === null) {
      throw new TypeError(
        `Module "${module}" needs table "${logical}", which blocks.${module}.tables maps to null`,
      );
    }

    const parts = splitTable(
      mapped ?? scoped(naming.rename(table.name), table.name),
      config.schema,
    );

    checkIdent(`${where}.tables.${logical}`, parts.schema);
    checkIdent(`${where}.tables.${logical}`, parts.name);

    return parts;
  };

  const tenantColumn = source.tenantColumn;

  if (tenantColumn !== undefined) {
    checkIdent("sql.tenantColumn", tenantColumn);
  }

  const column = (table: string, logical: string): string | null => {
    const known = names.tables[table];

    if (!known || !(logical in known.columns)) {
      throw new TypeError(
        `Module "${module}" has no column "${table}.${logical}"`,
      );
    }

    const mapped = config.columns[table]?.[logical];

    return mapped === undefined
      ? blockColumnName(
          { module, table },
          known.columns,
          known.columns[logical]!,
          tenantColumn,
          (name) => naming.rename(name),
        )
      : mapped;
  };

  const requiredColumn = (table: string, logical: string): string => {
    const name = column(table, logical);

    if (name === null) {
      throw new TypeError(
        `Module "${module}" needs ${table}.${logical}, which blocks.${module}.columns maps to null`,
      );
    }

    return name;
  };

  function optionOf(name: string, type: "string", fallback: string): string;
  function optionOf(name: string, type: "number", fallback: number): number;
  function optionOf(name: string, type: "boolean", fallback: boolean): boolean;
  function optionOf(
    name: string,
    type: "string" | "number" | "boolean",
    fallback: string | number | boolean,
  ): string | number | boolean {
    const value = option(name);

    if (value === undefined) {
      return fallback;
    }

    if (
      typeof value !== "string" &&
      typeof value !== "number" &&
      typeof value !== "boolean"
    ) {
      throw new TypeError(`${where}.options.${name} must be a ${type}`);
    }

    if (typeof value !== type) {
      throw new TypeError(`${where}.options.${name} must be a ${type}`);
    }

    return value;
  }

  const schema = sqlIdent(config.schema);

  const hookTarget = (written: string): string => {
    const name = names.hooks?.find(
      (hook) => hook === written || resolved.formerName(hook) === written,
    );

    if (name === undefined) {
      throw new TypeError(`Module "${module}" declares no hook "${written}"`);
    }

    const parts = splitTable(
      config.hooks.functions[name] ??
        config.hooks.functions[resolved.formerName(name)] ??
        scoped(entityNaming.rename(legacy(name)), name),
      config.hooks.schema,
    );

    return `${sqlIdent(parts.schema)}.${sqlIdent(parts.name)}`;
  };

  const installed = new Set(source.installed ?? [module]);
  const readable = source.integrations?.(module);

  const declares = (name: string): void => {
    if (readable && name !== module && !readable.has(name)) {
      throw new TypeError(
        `Module "${module}" reads module "${name}", which it neither requires nor lists in integrates`,
      );
    }
  };

  const checkEvent = (event: BlockSqlEmit): void => {
    if (!names.events) {
      return;
    }

    const spec: CheckedEventSpec | undefined = Object.entries(
      names.events,
    ).find(([type]) => type === event.type)?.[1];

    if (!spec) {
      throw new TypeError(
        `Module "${module}" records "${event.type}", which its names.events doesn't declare`,
      );
    }

    const fault = (problem: string): never => {
      throw new TypeError(
        `Module "${module}" event "${event.type}" ${problem}`,
      );
    };

    if (!SUBJECT_COLLECTION.test(spec.subject)) {
      fault(`has subject "${spec.subject}", not a kebab-case plural`);
    }

    if (!event.subject?.startsWith(`'${spec.subject}/`)) {
      fault(`needs a subject that starts with '${spec.subject}/'`);
    }

    const missing = spec.payload.filter(
      (key) => !event.payload.includes(`'${key}'`),
    );

    if (missing.length > 0) {
      fault(`payload lacks ${missing.join(", ")}`);
    }

    const tenanted = event.tenant !== undefined && event.tenant !== "null";

    if (tenanted && !spec.payload.includes("organizationId")) {
      fault("has a tenant, so its payload needs organizationId");
    }

    if (spec.retries === true && event.key === undefined) {
      fault("is written by a writer that retries, so it needs a key");
    }
  };

  // The written event: its type, subject collection and payload keys follow
  // the module's entity renames.
  const renamed = <E extends BlockSqlEmit>(event: E): E => {
    if (!entityNaming.renamed) {
      return event;
    }

    const spec = names.events?.[event.type];
    const prefix = spec === undefined ? undefined : `'${spec.subject}/`;

    const payload = (spec?.payload ?? []).reduce(
      (expression, key) =>
        expression.replaceAll(`'${key}'`, `'${entityNaming.rename(key)}'`),
      event.payload,
    );

    const subject =
      prefix !== undefined && event.subject?.startsWith(prefix) === true
        ? `'${entityNaming.rename(spec?.subject ?? "")}/${event.subject.slice(prefix.length)}`
        : event.subject;

    return {
      ...event,
      type: entityNaming.rename(event.type),
      payload,
      ...(subject === undefined ? {} : { subject }),
    };
  };

  const outbox = (checked: BlockSqlEmit): string => {
    checkEvent(checked);
    const event = renamed(checked);

    if (!config.events || !installed.has("outbox")) {
      return "";
    }

    const outboxConfig = resolveBlock(modules["outbox"]);

    const template =
      outboxConfig.options["blockSource"] ?? "better-supabase/{module}";

    if (typeof template !== "string") {
      throw new TypeError("blocks.outbox.options.blockSource must be a string");
    }

    return `perform ${sqlIdent(outboxConfig.schema)}.emit_event(${[
      sqlString(event.type),
      event.payload,
      event.subject ?? "null",
      event.tenant === undefined ? "null" : `(${event.tenant})::text`,
      event.key ?? "null",
      sqlString(template.replaceAll("{module}", instance)),
    ].join(", ")});`;
  };

  const auditEntry = (checked: BlockSqlAction): string => {
    const action = renamed(checked);
    const audit = action.audit;

    if (!audit || !config.audit || !installed.has("audit")) {
      return "";
    }

    // auditCategory is the deprecated per-module override of every category.
    const legacy = declared.has("auditCategory")
      ? config.options["auditCategory"]
      : undefined;

    if (legacy !== undefined && typeof legacy !== "string") {
      throw new TypeError(`${where}.options.auditCategory must be a string`);
    }

    const auditIdType =
      modules["audit"]?.idType ??
      modules.permissions?.idType ??
      source.providerIdType ??
      "uuid";

    const args: [string, string | undefined][] = [
      ["event_type", sqlString(action.type)],
      ["category", sqlString(legacy ?? audit.category)],
      [
        "target_type",
        audit.targetType && sqlString(entityNaming.rename(audit.targetType)),
      ],
      ["record_id", audit.recordId],
      ["target_label", audit.targetLabel],
      ["summary", audit.summary],
      [
        "tenant",
        action.tenant === undefined
          ? undefined
          : `(${action.tenant})::${auditIdType}`,
      ],
      ["metadata", audit.metadata ?? action.payload],
      ["idempotency_key", action.key],
      ["actor_id", audit.actor],
      ["support_session", audit.supportSession],
      ["impersonated_by", audit.impersonatedBy],
      ["impersonation_reason", audit.impersonationReason],
    ];

    return `perform better_supabase.audit_event(\n${args
      .filter((arg): arg is [string, string] => arg[1] !== undefined)
      .map(([name, value]) => `    ${name} => ${value}`)
      .join(",\n")}\n  );`;
  };

  // record_subject_read exists when subjects renders its functions, and logs
  // nothing for a type without auditReads.
  const logsReads =
    ["audit", "subjects"].every((name) => installed.has(name)) &&
    resolveBlock(modules["subjects"]).mode !== "custom" &&
    logsSubjectReads(source.subjects);

  const scope = moduleScope({
    kind: scopeKind,
    idType,
    access: installed.has("permissions"),
    guests: installed.has("guests") || source.providerGuests === true,
    members: () =>
      createModuleContext("memberships", namesOf, shared).fn(
        "member_organization_ids",
      ),
  });

  function entitlements(tenant: string): string | undefined;
  function entitlements(tenant: string, fallback: string): string;
  function entitlements(tenant: string, fallback?: string): string | undefined {
    declares("entitlements");

    return installed.has("entitlements")
      ? `better_supabase.tenant_entitlements(${tenant})`
      : fallback;
  }

  const lifecycle = (name: string, args: string): string | undefined => {
    declares("data-lifecycle");

    return installed.has("data-lifecycle")
      ? `${createModuleContext("data-lifecycle", namesOf, shared).fn(name)}(${args})`
      : undefined;
  };

  const retention = (
    kind: string,
    tenant: string,
    fallback: string,
  ): string => {
    const policy = lifecycle(
      "retention_for",
      `${sqlString(kind)}, (${tenant})::text`,
    );

    return policy ? `coalesce(${policy}, ${fallback})` : fallback;
  };

  const held = (kind: string, tenant: string): string =>
    lifecycle("is_held", `${sqlString(kind)}, (${tenant})::text`) ?? "false";

  const owned = tableOwnership(
    { module, tables: names.tables, config, source, tableName },
    column,
    requiredColumn,
  );

  const context: BlockSqlContext = {
    module,
    instance,
    on: modules[module]?.on,
    mode: config.mode,
    config,
    schema,
    schemaName: config.schema,
    idType,
    claims: source.claims ?? DEFAULT_CLAIMS,
    subjects: source.subjects ?? {},
    providerRowsWith: source.providerRowsWith,
    providerRowsWithFor: source.providerRowsWithFor,
    appTables: new Set(source.appTables),
    scope,
    resolved,
    naming,
    blockNaming: () =>
      composeNames(
        ...Object.entries(modules).flatMap(([name, block]) => {
          const known =
            block?.entities === undefined ? undefined : namesOf(name);

          return known === undefined
            ? []
            : [resolveNames(name, known, modules).entityNaming];
        }),
      ),
    contributions: (block) =>
      (shared.contributors?.(block) ?? [])
        .filter((contributor) => contributor.instance === instance)
        .flatMap((contributor) => contributor.contribute(context)),
    instanceNamings: () =>
      Object.entries(source.instances ?? {}).flatMap(([name, other]) => {
        const known = namesOf(other.block);

        return name === other.block || known === undefined
          ? []
          : [
              instanceEntityNames(
                other.block,
                name,
                resolveNames(other.block, known, {
                  ...shared.modules,
                  [other.block]: other.config,
                }).entityNaming,
              ),
            ];
      }),
    modules,
    manages: config.mode === "managed",
    ...owned,
    ...valueMethods({
      tables: names.tables,
      maps: checkedValueMaps(where, config.values, names.tables),
      cast: owned.cast,
      column: requiredColumn,
      mapped: (table, logical) =>
        config.tables[table] === null ? null : column(table, logical),
      own: (name) => naming.rename(name),
    }),
    names,
    installedModules: [...installed],
    fn: (name) =>
      FIXED_FUNCTIONS[module]?.has(name)
        ? `better_supabase.${fnName(name)}`
        : `${FIXED_FUNCTION_MODULES.has(module) ? sqlIdent("better_supabase") : schema}.${sqlIdent(fnName(name))}`,
    fnName,
    functionRenames: () => applied,
    unusedFunctions: () =>
      Object.keys(renames).filter((name) => !requested.has(name)),
    table(logical) {
      const parts = owned.tableName(logical);

      return `${sqlIdent(parts.schema)}.${sqlIdent(parts.name)}`;
    },
    colName: (table, logical) => requiredColumn(table, logical),
    has: (table, logical) =>
      config.tables[table] !== null && column(table, logical) !== null,
    hasTable: (table) => {
      if (!names.tables[table]) {
        throw new TypeError(`Module "${module}" has no table "${table}"`);
      }

      return config.tables[table] !== null;
    },
    permissionKey: (action, fallback) =>
      config.permissions[action] ?? ownKey(fallback),
    permission: (action, fallback) =>
      sqlString(config.permissions[action] ?? ownKey(fallback)),
    trigger: (name) =>
      sqlIdent(`bsb_${scoped(naming.rename(legacy(name)), name)}`),
    installed(name) {
      declares(name);

      return installed.has(name);
    },
    of(name) {
      declares(name);
      const bound = entry?.uses[name];

      const source =
        bound === undefined ? shared : { ...shared, instance: bound };

      return createModuleContext(name, namesOf, source);
    },
    text: (name, fallback) => optionOf(name, "string", fallback),
    number: (name, fallback) => optionOf(name, "number", fallback),
    flag: (name, fallback) => optionOf(name, "boolean", fallback),
    option,
    list(name, fallback) {
      const value = option(name);

      if (value === undefined) {
        return fallback;
      }

      if (
        !Array.isArray(value) ||
        !value.every((item) => typeof item === "string")
      ) {
        throw new TypeError(`${where}.options.${name} must be a string array`);
      }

      return value;
    },
    extraColumns(table, reserved = [], key = "extraColumns") {
      const value = option(key);

      if (value === undefined) {
        return [];
      }

      const at = `${where}.options.${key}`;

      if (typeof value !== "object" || value === null || Array.isArray(value)) {
        throw new TypeError(`${at} must be an object`);
      }

      const known = names.tables[table];

      if (!known) {
        throw new TypeError(`Module "${module}" has no table "${table}"`);
      }

      const taken = new Set([
        ...reserved,
        ...Object.keys(known.columns)
          .filter((logical) => !known.yieldsToExtra?.includes(logical))
          .flatMap((logical) => column(table, logical) ?? []),
      ]);

      return checkedExtraColumns(at, value, taken);
    },
    hook(name, args) {
      const target = hookTarget(name);
      const types = args.map(([type]) => type).join(", ");
      const params = args.map(([type], i) => `$${String(i + 1)}::${type}`);

      return `declare
    v_hook regprocedure := to_regprocedure(${sqlString(`${target}(${types})`)});
  begin
    if v_hook is not null then
      execute format('select %s(${params.join(", ")})', v_hook::oid::regproc)${
        args.length > 0
          ? `\n        using ${args.map(([, value]) => value).join(", ")}`
          : ""
      };
    end if;
  end;`;
    },
    hookTarget,
    emit: outbox,
    record(action) {
      const parts = [outbox(action), auditEntry(action)].filter(
        (part) => part !== "",
      );

      return parts.length === 0 ? NOTHING : parts.join("\n  ");
    },
    audit(action) {
      checkEvent(action);
      const entry = auditEntry(action);

      return entry === "" ? NOTHING : entry;
    },
    read: (subjectType, subjectId, fnName) =>
      logsReads
        ? `perform ${createModuleContext("subjects", namesOf, shared).fn("record_subject_read")}(${subjectType}, ${subjectId}, null, ${sqlString(instance)}, ${sqlString(fnName)});`
        : "",
    readVolatility: () => (logsReads ? "volatile" : "stable"),
    notify(fields, options = {}) {
      declares("notifications");

      if (!installed.has("notifications")) {
        return NOTHING;
      }

      const indent = options.indent ?? "  ";
      const target = createModuleContext("notifications", namesOf, shared);

      return [
        "v_claims := current_setting('request.jwt.claims', true);",
        `perform set_config('request.jwt.claims', '{"role": "service_role"}', true);`,
        `perform ${target.fn("notify")}(${fields});`,
        "perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);",
      ].join(`\n${indent}`);
    },
    enqueue(queue, payload, dedupe, options = {}) {
      declares("queue");

      if (!installed.has("queue")) {
        return NOTHING;
      }

      const jobs = createModuleContext("queue", namesOf, shared);

      const delay =
        options.delay === undefined ? "" : `, delay => ${options.delay}`;

      return `perform ${jobs.fn("enqueue_job")}(queue => ${sqlString(queue)}, payload => ${payload}${delay}, dedupe_key => ${dedupe}, dedupe_running => false);`;
    },
    automation(spec) {
      const needs = spec.requires ?? [];

      for (const name of ["automations", ...needs]) {
        declares(name);
      }

      if (!["automations", ...needs].every((name) => installed.has(name))) {
        return "";
      }

      const rules = createModuleContext("automations", namesOf, shared);

      if (rules.mode === "custom") {
        return "";
      }

      return defaultRuleRow(
        rules,
        instance,
        (name) => entityNaming.rename(name),
        { ...spec, enabled: shipsEnabled(rules, spec) },
      );
    },
    entitlements,
    retention,
    held,
    expired(kind, row) {
      const floor = lifecycle("retention_floor", sqlString(kind));

      return floor === undefined
        ? `${row.at} < now() - ${row.fallback}`
        : `(${row.at} < now() - least(${row.fallback}, ${floor})
      and ${row.at} < now() - ${retention(kind, row.tenant, row.fallback)}
      and not ${held(kind, row.tenant)})`;
    },
    cutoff(kind, fallback) {
      return (
        lifecycle("retention_cutoff", `${sqlString(kind)}, ${fallback}`) ??
        `now() - ${fallback}`
      );
    },
    broadcast(topic, event, payload, options = {}) {
      const indent = options.indent ?? "  ";

      return `if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
${indent}  perform realtime.send(${payload}, ${event}, ${topic}, true);
${indent}end if;`;
    },
    can: (name, id, permission) =>
      name === "tenant"
        ? scope.can(id, permission)
        : `coalesce(better_supabase.can(${sqlString(name)}, ${id}, ${permission}), false)`,
    staff(permission) {
      declares("permissions");

      return installed.has("permissions")
        ? `(${SERVICE_CALLER} or ${scope.platform(permission)})`
        : SERVICE_CALLER;
    },
  };

  return context;
}

/** The contract's argument list with `{id}` resolved, as Postgres prints it. */
export function contractSignature(
  fn: BlockSqlContractFunction,
  idType: string,
): string {
  return fn.args.map((arg) => arg.replaceAll("{id}", idType)).join(", ");
}
