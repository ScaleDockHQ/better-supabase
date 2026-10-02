import type { Operation, Selection } from "../../ir/types.ts";
import type { SchemaMeta, TableMeta } from "../../schema/types.ts";

import { claimAt, claimsOf } from "../../core/claims.ts";
import { dbError, DbException } from "../../core/errors.ts";
import {
  definePlugin,
  type HookArgs,
  type Plugin,
  type RepositoryExtension,
} from "../../core/plugin.ts";

export type RuleLevel = "off" | "warn" | "error";

/** A level, or a level with the rule's option: `['error', 500]`. */
export type RuleSetting<Option = never> =
  | RuleLevel
  | ([Option] extends [never] ? never : readonly [RuleLevel, Option]);

export interface RuleSet {
  /** `findMany` without `limit` (reads the whole table). */
  readonly noUnboundedFindMany?: RuleSetting;
  /** `limit` above the given maximum (default 1000). */
  readonly maxLimit?: RuleSetting<number>;
  /**
   * Paging (`offset`, or `limit` above 1) without `orderBy`: Postgres returns
   * rows in no particular order, so pages overlap or skip rows. `findMany`
   * orders by the primary key by default, so this only fires on views and
   * tables without one.
   */
  readonly requireOrderByForCursor?: RuleSetting;
  /** Includes nested deeper than the given depth (default 3). */
  readonly maxIncludeDepth?: RuleSetting<number>;
  /**
   * Tenant tables queried without a tenant: neither `context.tenant` nor the
   * given claim (default `config.claims.tenant`, `tenant_id`). Service
   * connections are exempt.
   */
  readonly requireTenantContext?: RuleSetting<string>;
  /** A service-role connection used where `window` and `document` exist. */
  readonly noAdminInBrowser?: RuleSetting;
  /**
   * Reads of columns listed in `config.sensitive` without `sensitive: true`
   * on the call.
   */
  readonly noSensitiveSelect?: RuleSetting;
  /**
   * Delete operations without `where`. The repository refuses `deleteMany`
   * without `where` on its own, so this catches deletes built by plugins;
   * the lint rule of the same name flags the call in the editor.
   */
  readonly noDeleteManyWithoutWhere?: RuleSetting;
  /**
   * Storage objects written to `*_url` text columns: a column listed in
   * `storagePaths`, or a value that is a Storage URL or matches a bucket's
   * path template. Signed URLs expire and public URLs pin the project host,
   * so store the path in a `*_path` column and build URLs when rendering.
   */
  readonly storagePathColumns?: RuleSetting;
}

export type RuleName = keyof RuleSet;

export interface RuleViolation {
  readonly rule: RuleName;
  readonly level: "warn" | "error";
  readonly table: string;
  readonly operation: Operation["kind"];
  readonly message: string;
}

export interface RulesOptions {
  readonly rules?: RuleSet;
  /**
   * Called for every violation. Defaults to `console.warn` for warnings.
   * Errors fail the call with `invalid_request` after reporting.
   */
  readonly report?: (violation: RuleViolation) => void;
}

export interface RulesFindArgs {
  /** Allow reading `config.sensitive` columns in this call. */
  readonly sensitive?: boolean;
}

export interface RulesExtension extends RepositoryExtension {
  readonly findArgs: RulesFindArgs;
}

/** Catches data-exposure and correctness mistakes; everything else off. */
export function safe(): RuleSet {
  return {
    noAdminInBrowser: "error",
    noDeleteManyWithoutWhere: "error",
    noSensitiveSelect: "error",
    requireTenantContext: "error",
  };
}

/** `safe()` plus performance warnings. */
export function recommended(): RuleSet {
  return {
    ...safe(),
    noUnboundedFindMany: "warn",
    maxLimit: ["warn", 1000],
    requireOrderByForCursor: "warn",
    maxIncludeDepth: ["warn", 3],
    storagePathColumns: "warn",
  };
}

/** Every rule as an error. */
export function strict(): RuleSet {
  return {
    ...safe(),
    noUnboundedFindMany: "error",
    maxLimit: ["error", 1000],
    requireOrderByForCursor: "error",
    maxIncludeDepth: ["error", 3],
    storagePathColumns: "error",
  };
}

function levelOf(setting: RuleSetting<unknown> | undefined): RuleLevel {
  if (setting === undefined) return "off";
  return typeof setting === "string" ? setting : setting[0];
}

function optionOf<T>(setting: RuleSetting<T> | undefined, fallback: T): T {
  // SAFETY: a rule setting is a level or a [level, options] tuple, and
  // Array.isArray picked the tuple.
  return Array.isArray(setting)
    ? (setting as readonly [RuleLevel, T])[1]
    : fallback;
}

function includeDepth(selection: Selection): number {
  let depth = 0;
  for (const include of selection.includes) {
    if (include.count !== undefined || include.aggregate !== undefined)
      depth = Math.max(depth, 1);
    else depth = Math.max(depth, 1 + includeDepth(include.selection));
  }
  return depth;
}

function sensitiveColumns(selection: Selection, table: TableMeta): string[] {
  const found: string[] = [];
  const sensitive = new Set(
    Object.values(table.columns)
      .filter((column) => column.sensitive)
      .map((column) => column.db),
  );
  const columns = [
    ...selection.columns,
    ...(selection.aggregate?.measures ?? []),
  ];
  for (const column of columns) {
    if (sensitive.has(column.column))
      found.push(`${table.key}.${column.column}`);
  }
  for (const include of selection.includes) {
    found.push(...sensitiveColumns(include.selection, include.target));
  }
  return found;
}

function isBrowser(): boolean {
  // SAFETY: window and document are only read to check whether they exist.
  return (
    (globalThis as { window?: unknown }).window !== undefined &&
    (globalThis as { document?: unknown }).document !== undefined
  );
}

const TEXT_TYPES = new Set(["text", "varchar", "bpchar"]);
const STORAGE_URL =
  /\/storage\/v1\/(?:object|render\/image)\/(?:public|sign|authenticated)\//;

const templatesBySchema = new WeakMap<SchemaMeta, readonly RegExp[]>();

/** Bucket templates specific enough to identify a path: some literal text besides `/`. */
function bucketTemplates(schema: SchemaMeta): readonly RegExp[] {
  let templates = templatesBySchema.get(schema);
  if (!templates) {
    templates = Object.values(schema.buckets ?? {})
      .filter(
        (bucket) => bucket.path.replaceAll(/\{[^}]*\}|\//g, "").length > 0,
      )
      .map(
        (bucket) =>
          new RegExp(
            `^${bucket.path
              .split(/\{[^}]*\}/)
              .map((part) => part.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&"))
              .join("[^/]+")}$`,
          ),
      );
    templatesBySchema.set(schema, templates);
  }
  return templates;
}

function storedObjectColumn(
  op: Operation,
  schema: SchemaMeta,
): string | undefined {
  const rows =
    op.kind === "insert" ? op.rows : op.kind === "update" ? [op.set] : [];
  if (rows.length === 0) return undefined;
  for (const column of Object.values(op.table.columns)) {
    if (
      !rows.some((row) => column.db in row) ||
      !column.db.endsWith("_url") ||
      column.array ||
      !TEXT_TYPES.has(column.type)
    )
      continue;
    const path = `${column.db.slice(0, -4)}_path`;
    if (column.storage !== undefined)
      return `"${column.db}" holds paths in bucket "${column.storage}"; name it "${path}"`;
    const stored = rows.some((row) => {
      const value = row[column.db];
      return (
        typeof value === "string" &&
        (STORAGE_URL.test(value) ||
          bucketTemplates(schema).some((template) => template.test(value)))
      );
    });
    if (stored)
      return `"${column.db}" is given a storage object; store its path in "${path}" and build URLs with signedUrl() or renderUrl()`;
  }
  return undefined;
}

type Check = (op: Operation, hook: HookArgs) => string | undefined;

function checks(rules: RuleSet): Record<RuleName, Check> {
  return {
    noUnboundedFindMany: (op) =>
      op.kind === "select" &&
      op.single === undefined &&
      !op.head &&
      op.limit === undefined
        ? "findMany without limit reads every visible row"
        : undefined,
    maxLimit: (op) => {
      const max = optionOf(rules.maxLimit, 1000);
      return op.kind === "select" && op.limit !== undefined && op.limit > max
        ? `limit ${op.limit} is above the maximum of ${max}`
        : undefined;
    },
    requireOrderByForCursor: (op) =>
      op.kind === "select" &&
      !op.head &&
      op.orderBy.length === 0 &&
      (op.offset !== undefined || (op.limit !== undefined && op.limit > 1))
        ? "paging without orderBy returns rows in no stable order"
        : undefined,
    maxIncludeDepth: (op) => {
      const max = optionOf(rules.maxIncludeDepth, 3);
      const selection = op.kind === "select" ? op.selection : op.returning;
      const depth = selection ? includeDepth(selection) : 0;
      return depth > max
        ? `includes nest ${depth} levels deep (maximum ${max})`
        : undefined;
    },
    requireTenantContext: (op, { context, schema }) => {
      if (!op.table.flags.tenant || context.actor?.kind === "service") return;
      const claim = optionOf(
        rules.requireTenantContext,
        claimsOf(schema).tenant,
      );
      return context.tenant === undefined &&
        claimAt(context.claims, claim) === undefined
        ? `"${op.table.key}" is tenant-scoped but the request has no tenant (context.tenant or claim "${claim}")`
        : undefined;
    },
    noAdminInBrowser: (_op, { context }) =>
      context.actor?.kind === "service" && isBrowser()
        ? "a service-role connection is running in a browser"
        : undefined,
    noSensitiveSelect: (op, { options }) => {
      if (options["sensitive"] === true) return;
      const selection = op.kind === "select" ? op.selection : op.returning;
      const columns = selection ? sensitiveColumns(selection, op.table) : [];
      return columns.length > 0
        ? `reads sensitive column(s) ${columns.join(", ")}; pass { sensitive: true } to allow`
        : undefined;
    },
    noDeleteManyWithoutWhere: (op) =>
      op.kind === "delete" && op.where === undefined
        ? "delete without where removes every visible row"
        : undefined,
    storagePathColumns: (op, { schema }) => storedObjectColumn(op, schema),
  };
}

function defaultReport(violation: RuleViolation): void {
  if (violation.level === "warn") {
    console.warn(
      `[better-supabase] ${violation.rule} (${violation.table}): ${violation.message}`,
    );
  }
}

/**
 * Runtime query rules, checked before each request is built:
 *
 * ```ts
 * defineSupabase(schema, { plugins: [rules({ rules: recommended() })] });
 * ```
 *
 * Runs first (`enforce: 'pre'`) so it sees the query as written, before
 * tenant or soft-delete filters are added. Pair with the static
 * `better-supabase/lint` plugin to catch the same mistakes in the editor.
 */
export function rules(
  options: RulesOptions = {},
): Plugin<"rules", RulesExtension> {
  const set = options.rules ?? recommended();
  const report = options.report ?? defaultReport;
  const all = checks(set);
  // SAFETY: checks() returns one entry per rule name, and Object.keys widens
  // the keys to string.
  const active = (Object.keys(all) as RuleName[]).flatMap((rule) => {
    const level = levelOf(set[rule]);
    return level === "off" ? [] : [{ rule, level, check: all[rule] }];
  });

  return definePlugin<"rules", RulesExtension>({
    name: "rules",
    enforce: "pre",
    transformQuery(op, hook): Operation {
      for (const { rule, level, check } of active) {
        const message = check(op, hook);
        if (message === undefined) continue;
        const violation: RuleViolation = {
          rule,
          level,
          table: op.table.key,
          operation: op.kind,
          message,
        };
        report(violation);
        if (level === "error") {
          throw new DbException(
            dbError("invalid_request", `${rule}: ${message}`, {
              table: op.table.key,
            }),
          );
        }
      }
      return op;
    },
  });
}
