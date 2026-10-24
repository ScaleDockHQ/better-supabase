import type {
  CatalogPolicy,
  CatalogTable,
  ExtrasFunction,
} from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule, SqlObject } from "./rules.ts";

import { moduleHidingColumns, moduleLayout } from "../../sql/index.ts";
import { splinterTables } from "./advisor-rules.ts";
import { appAndBlockPolicy } from "./block-policies.ts";
import {
  catalogOf,
  exposed,
  policyObject,
  qualified,
  tableObject,
} from "./shared.ts";

export const escape = (name: string): string =>
  name.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** `'it''s'` and other string literals, blanked so their text can't match. */
export const withoutStrings = (text: string): string =>
  text.replaceAll(/'(?:[^']|'')*'/g, "''");

const functionName = (fn: Pick<ExtrasFunction, "schema" | "name">): string =>
  `${fn.schema}.${fn.name}`;

export const functionObject = (fn: ExtrasFunction): SqlObject => ({
  kind: "function",
  schema: fn.schema,
  name: fn.name,
});

/** The functions policies call, by `schema.name`; overloads share a key. */
function functionsByName(
  context: DoctorContext,
): Map<string, ExtrasFunction[]> {
  const map = new Map<string, ExtrasFunction[]>();

  for (const fn of context.snapshot.extras.functions ?? []) {
    const key = functionName(fn);
    const list = map.get(key);

    if (list) {
      list.push(fn);
    } else {
      map.set(key, [fn]);
    }
  }

  return map;
}

/** Argument lists of every call to `schema.name(...)` in an expression. */
function callArguments(
  expression: string | null,
  fn: Pick<ExtrasFunction, "schema" | "name">,
): string[] {
  if (!expression) {
    return [];
  }

  const text = withoutStrings(expression);

  const pattern = new RegExp(
    `(?<![\\w."])(?:"?${escape(fn.schema)}"?\\.)?"?${escape(fn.name)}"?\\s*\\(`,
    "g",
  );

  const calls: string[] = [];

  for (const match of text.matchAll(pattern)) {
    const start = match.index + match[0].length;
    let depth = 1;
    let end = start;

    while (end < text.length && depth > 0) {
      if (text[end] === "(") {
        depth += 1;
      } else if (text[end] === ")") {
        depth -= 1;
      }

      end += 1;
    }

    calls.push(text.slice(start, end - 1));
  }

  return calls;
}

/**
 * The first column of `table` an argument list refers to, bare or as
 * `table.column`.
 */
function columnArgument(args: string, table: CatalogTable): string | undefined {
  return table.columns.find((column) =>
    new RegExp(
      `(?<![\\w."$:])(?:"?${escape(table.name)}"?\\.)?"?${escape(column.name)}"?(?![\\w"(.$])`,
    ).test(args),
  )?.name;
}

const expressions = (policy: CatalogPolicy): (string | null)[] => [
  policy.using,
  policy.check,
];

/**
 * Why Postgres can't inline `fn` into the query that calls it, or `undefined`
 * when it can: only `language sql` functions that are not volatile, not
 * security definer and have no `set` options are inlined.
 */
function notInlinable(fn: ExtrasFunction): string | undefined {
  if (fn.language !== "sql") {
    return `a ${fn.language} function`;
  }

  if (fn.volatility === "volatile") {
    return "a volatile function";
  }

  if (fn.securityDefiner) {
    return "a security definer function";
  }

  const settings = Object.keys(fn.settings);

  if (settings.length > 0) {
    return `a function with \`set ${settings.join(", ")}\``;
  }

  return undefined;
}

const rlsTables = (context: DoctorContext): CatalogTable[] =>
  exposed(context).filter((table) => table.rls);

export const COMMANDS = ["select", "insert", "update", "delete"] as const;

/** Policies apply to every role when they list `public` or none. */
export const appliesTo = (policy: CatalogPolicy, role: string): boolean =>
  policy.roles.length === 0 ||
  policy.roles.includes("public") ||
  policy.roles.includes(role);

export interface PermissiveOverlap {
  readonly command: (typeof COMMANDS)[number];
  readonly role: string;
  readonly policies: readonly string[];
}

/** Commands and roles that more than one permissive policy of the table covers. */
function permissiveOverlaps(table: CatalogTable): PermissiveOverlap[] {
  const permissive = table.policies.filter((policy) => policy.permissive);
  const roles = new Set<string>();

  for (const policy of permissive) {
    const named = policy.roles.filter((role) => role !== "public");

    if (named.length < policy.roles.length || policy.roles.length === 0) {
      roles.add("anon");
      roles.add("authenticated");
    }

    for (const role of named) {
      roles.add(role);
    }
  }

  const overlaps: PermissiveOverlap[] = [];

  for (const command of COMMANDS) {
    for (const role of [...roles].toSorted()) {
      const policies = permissive
        .filter(
          (policy) =>
            (policy.command === "all" || policy.command === command) &&
            appliesTo(policy, role),
        )
        .map((policy) => policy.name);

      if (policies.length > 1) {
        overlaps.push({ command, role, policies });
      }
    }
  }

  return overlaps;
}

const WRITES = ["insert", "update"] as const;
const API_ROLES = ["anon", "authenticated"] as const;

const NOT_ALIAS = new Set([
  "where",
  "join",
  "inner",
  "left",
  "right",
  "full",
  "cross",
  "on",
  "using",
  "group",
  "order",
  "limit",
  "union",
  "natural",
  "lateral",
  "as",
]);

interface GrantColumn {
  /** The helpers that read the column, as `schema.name`. */
  readonly helpers: Set<string>;
  /** Listed in the authorization provider's `decidingColumns`. */
  provider: boolean;
}

/**
 * The body of `schema.name` from the snapshot, else from the first SQL file
 * that creates it.
 */
export function functionBody(
  context: DoctorContext,
  schema: string,
  name: string,
): string | undefined {
  const introspected = context.snapshot.generator.functions.find(
    (fn) => fn.schema === schema && fn.name === name && fn.definition,
  )?.definition;

  if (introspected) {
    return introspected;
  }

  const creates = new RegExp(
    `create\\s+(?:or\\s+replace\\s+)?function\\s+(?:"?${escape(schema)}"?\\.)?"?${escape(name)}"?\\s*\\([\\s\\S]*?\\bas\\s+(\\$\\w*\\$)([\\s\\S]*?)\\1`,
    "i",
  );

  for (const file of context.sqlFiles ?? []) {
    const match = creates.exec(file.text);

    if (match) {
      return match[2];
    }
  }

  return undefined;
}

const helpersByContext = new WeakMap<
  DoctorContext,
  ReadonlyMap<string, string>
>();

/** The functions policies call, and the functions those call, with their bodies. */
export function policyHelpers(
  context: DoctorContext,
): ReadonlyMap<string, string> {
  let helpers = helpersByContext.get(context);

  if (!helpers) {
    helpers = findPolicyHelpers(context);
    helpersByContext.set(context, helpers);
  }

  return helpers;
}

function findPolicyHelpers(context: DoctorContext): Map<string, string> {
  const known = context.snapshot.generator.functions;

  const queue = catalogOf(context).tables.flatMap((table) =>
    table.policies.flatMap((policy) => policy.functions ?? []),
  );

  const bodies = new Map<string, string>();

  while (queue.length > 0) {
    const key = queue.pop()!;

    if (bodies.has(key)) {
      continue;
    }

    const dot = key.indexOf(".");
    const body = functionBody(context, key.slice(0, dot), key.slice(dot + 1));

    if (!body) {
      continue;
    }

    const text = withoutStrings(body);
    bodies.set(key, text);

    for (const fn of known) {
      const called = `${fn.schema}.${fn.name}`;

      if (!bodies.has(called) && callArguments(text, fn).length > 0) {
        queue.push(called);
      }
    }
  }

  return bodies;
}

/**
 * Tables a function body reads (`from` and `join`), with the names it refers to
 * them by.
 */
function readTables(
  body: string,
  tables: readonly CatalogTable[],
): { table: CatalogTable; names: string[] }[] {
  const found = new Map<CatalogTable, Set<string>>();

  const pattern =
    /\b(?:from|join)\s+(?:"?(\w+)"?\s*\.\s*)?"?(\w+)"?(?:\s+(?:as\s+)?"?(\w+)"?)?/gi;

  for (const match of body.matchAll(pattern)) {
    const [, schema, name, alias] = match;

    const table =
      tables.find((t) => t.name === name && t.schema === schema) ??
      (schema
        ? undefined
        : (tables.find((t) => t.name === name && t.schema === "public") ??
          tables.find((t) => t.name === name)));

    if (!table) {
      continue;
    }

    const names = found.get(table) ?? new Set([table.name]);

    if (alias && !NOT_ALIAS.has(alias.toLowerCase())) {
      names.add(alias);
    }

    found.set(table, names);
  }

  return [...found].map(([table, names]) => ({ table, names: [...names] }));
}

/**
 * Columns that decide who may read other rows, by `schema.table`: the columns
 * of the tables policy helpers read that their bodies mention (qualified, or
 * bare when the body reads one table), and the manifest's `decidingColumns`. A
 * subject's `deletedAt` column and a module's `hidingColumns` only hide rows,
 * so they count only when the manifest lists them.
 */
function grantColumns(
  context: DoctorContext,
): Map<string, Map<string, GrantColumn>> {
  const tables = catalogOf(context).tables;
  const columns = new Map<string, Map<string, GrantColumn>>();

  const entry = (table: string, column: string): GrantColumn => {
    const byColumn = columns.get(table) ?? new Map<string, GrantColumn>();
    columns.set(table, byColumn);
    const existing = byColumn.get(column);

    if (existing) {
      return existing;
    }

    const created: GrantColumn = { helpers: new Set(), provider: false };
    byColumn.set(column, created);

    return created;
  };

  const softDeleted = new Set([
    ...Object.values(context.config.subjects).flatMap((subject) =>
      subject.deletedAt === undefined
        ? []
        : [
            `${subject.table.includes(".") ? subject.table : `public.${subject.table}`}.${subject.deletedAt}`,
          ],
    ),
    ...(context.config.blockNames.length > 0
      ? moduleHidingColumns(
          context.config.blockNames,
          moduleLayout(context.config),
        )
      : []),
  ]);

  for (const [helper, body] of policyHelpers(context)) {
    const read = readTables(body, tables);

    for (const { table, names } of read) {
      for (const column of table.columns) {
        if (softDeleted.has(`${qualified(table)}.${column.name}`)) {
          continue;
        }

        const col = `"?${escape(column.name)}"?(?![\\w"(])`;

        const qualifiedColumn = new RegExp(
          `(?<![\\w"])(?:${names.map((name) => `"?${escape(name)}"?`).join("|")})\\s*\\.\\s*${col}`,
          "i",
        );

        const bare = new RegExp(`(?<![\\w."])${col}`, "i");

        if (
          qualifiedColumn.test(body) ||
          (read.length === 1 && bare.test(body))
        ) {
          entry(qualified(table), column.name).helpers.add(helper);
        }
      }
    }
  }

  for (const deciding of context.config.authorization?.decidingColumns ?? []) {
    const dot = deciding.lastIndexOf(".");

    if (dot > 0) {
      entry(deciding.slice(0, dot), deciding.slice(dot + 1)).provider = true;
    }
  }

  return columns;
}

/**
 * Whether `role` may run `command` on rows of `table` at all: no RLS, or a
 * permissive policy for it.
 */
const policyAllows = (
  table: CatalogTable,
  command: (typeof WRITES)[number],
  role: string,
): boolean =>
  !table.rls ||
  table.policies.some(
    (policy) =>
      policy.permissive &&
      (policy.command === "all" || policy.command === command) &&
      appliesTo(policy, role),
  );

/**
 * Whether `grant` reaches `role`: granted to it, or to PUBLIC, which every role
 * inherits.
 */
const grantsTo = (grant: { readonly role: string }, role: string): boolean =>
  grant.role === role || grant.role === "PUBLIC";

/**
 * Constant arguments, as Postgres prints them back: string literals with an
 * optional cast, numbers, booleans and null.
 */
const LITERAL_ARGS = String.raw`(?:\s*(?:'(?:[^']|'')*'(?:::[\w ]+(?:\[\])?)?|-?\d+(?:\.\d+)?|true|false|null)\s*,?)*\s*`;

/**
 * Whether every call of `name` (`schema.function`) in `expressions` takes only
 * constant arguments inside `(select ...)`, which Postgres runs once per
 * statement. An argument from the row makes it run per row.
 */
function onlyWrapped(
  name: string,
  expressions: readonly (string | null | undefined)[],
): boolean {
  const dot = name.indexOf(".");

  const call = `"?${escape(name.slice(0, dot))}"?\\s*\\.\\s*"?${escape(name.slice(dot + 1))}"?\\s*\\(`;

  const any = new RegExp(`(?<![\\w."])${call}`, "gi");

  const wrapped = new RegExp(
    `\\(\\s*select\\s+${call}${LITERAL_ARGS}\\)(?:\\s+as\\s+"?\\w+"?)?\\s*\\)`,
    "gi",
  );

  let calls = 0;
  let wraps = 0;

  for (const expression of expressions) {
    if (expression) {
      calls += expression.match(any)?.length ?? 0;
      wraps += expression.match(wrapped)?.length ?? 0;
    }
  }

  return calls > 0 && calls === wraps;
}

/**
 * Whether every permissive policy that lets `role` run `command` holds `column`
 * to a tenant the caller acts in, with no `or` around it: equal to
 * `current_tenant_id()`, passed to `can('tenant', column, ...)`, or in `(select
 * tenant_ids_with(...))` or `(select member_<tenant>_ids())`. A write can't
 * name a tenant the caller isn't in then. The guest branch `ctx.scope.guest`
 * adds (`or (column, ...) in (select g.tenant ... portal_subjects(...) g)`)
 * pins it to a tenant the caller is a guest of, so it doesn't count as an
 * `or`.
 */
function pinnedToTenant(
  table: CatalogTable,
  column: string,
  command: (typeof WRITES)[number],
  role: string,
): boolean {
  if (!table.rls) {
    return false;
  }

  const col = `"?${escape(column)}"?`;

  const pin = new RegExp(
    [
      `(?<![\\w."])${col}\\s*=\\s*\\(?\\s*(?:select\\s+)?better_supabase\\.current_tenant_id\\(\\)`,
      `better_supabase\\.can\\(\\s*'tenant'(?:::text)?\\s*,\\s*${col}\\s*,`,
      `(?<![\\w."])${col}\\s+in\\s+\\(\\s*select\\s+better_supabase\\.(?:tenant_ids_with|member_\\w+_ids)\\(`,
    ].join("|"),
    "i",
  );

  const guest = new RegExp(
    `\\bor\\s+\\(*\\(?${col}\\)?(?:::text)?\\s*,(?:[^()]|\\([^()]*\\))*\\)\\s+in\\s+\\(\\s*select\\s+g\\.tenant\\b[^()]*from\\s+better_supabase\\.portal_(?:subjects|parties)\\([^()]*\\)\\s+g(?:\\([^()]*\\))?\\)`,
    "gi",
  );

  const applying = table.policies.filter(
    (policy) =>
      policy.permissive &&
      (policy.command === "all" || policy.command === command) &&
      appliesTo(policy, role),
  );

  return (
    applying.length > 0 &&
    applying.every((policy) => {
      const check = (policy.check ?? policy.using)?.replaceAll(guest, "");

      return check !== undefined && !/\bor\b/i.test(check) && pin.test(check);
    })
  );
}

/**
 * The grant columns `role` may write with `command`, through a table-level or a
 * column-level grant. A single-column primary key is left out (its uniqueness
 * stops a write from taking over another row), and so is a column every policy
 * pins to the request's tenant, unless the provider lists it in `deciding`.
 */
function writableColumns(
  table: CatalogTable,
  columns: readonly string[],
  command: (typeof WRITES)[number],
  role: string,
  deciding: ReadonlySet<string> = new Set(),
): string[] {
  if (!policyAllows(table, command, role)) {
    return [];
  }

  const privilege = command.toUpperCase();

  const tableLevel = table.grants.some(
    (grant) => grantsTo(grant, role) && grant.privileges.includes(privilege),
  );

  const risky = columns.filter(
    (column) =>
      deciding.has(column) ||
      (!(table.primaryKey.length === 1 && table.primaryKey[0] === column) &&
        !pinnedToTenant(table, column, command, role)),
  );

  if (tableLevel) {
    return risky;
  }

  return risky.filter((column) =>
    (table.columnGrants ?? []).some(
      (grant) =>
        grantsTo(grant, role) &&
        grant.column === column &&
        grant.privileges.includes(privilege),
    ),
  );
}

/** PostgREST's default for `db-hoisted-tx-settings`. */
const DEFAULT_HOISTED = [
  "statement_timeout",
  "plan_filter.statement_cost_limit",
  "default_transaction_isolation",
];

const TIMEOUT_ROLES = ["anon", "authenticated", "authenticator"] as const;

/**
 * Partitions of an RLS table that have RLS off: queried by name, they skip the
 * parent's policies.
 */
function partitionsWithoutRls(context: DoctorContext): FindingInput[] {
  const tables = catalogOf(context).tables;
  const byName = new Map(tables.map((table) => [qualified(table), table]));

  return tables.flatMap((table): FindingInput[] => {
    if (
      table.partitionOf === undefined ||
      table.rls ||
      !context.config.schemas.includes(table.schema)
    ) {
      return [];
    }

    const parent = byName.get(table.partitionOf);

    if (!parent?.rls) {
      return [];
    }

    return [
      {
        message: `${qualified(table)} is a partition of ${table.partitionOf}, which has RLS on, but RLS is off on the partition. A query that names the partition skips the parent's policies, and Data API roles with a grant on it read every row. Run \`alter table ${qualified(table)} enable row level security;\`, and add the same enable to the code that creates new partitions.`,
        target: qualified(table),
        object: tableObject(table),
      },
    ];
  });
}

export const RLS_RULES: readonly Rule[] = [
  {
    code: "BS343",
    severity: "error",
    title: "Partition without row level security",
    description:
      "A table in `schemas` is a partition of a table with RLS on, but has RLS off itself. Policies belong to the parent, so a query that names the partition (`select * from events_default`) never applies them. This includes the default partition. Enable RLS on every partition when you create it; the partition functions of the SQL modules (`ensure_partitions`, ADR 0038) already do.",
    check: partitionsWithoutRls,
  },
  {
    code: "BS205",
    severity: "warning",
    title: "Policy calls a slow function once per row",
    description:
      "A policy passes a column of the row to a function Postgres cannot inline: plpgsql, volatile, security definer, or with a `set` option such as `search_path`. It runs once for every row the query reads.",
    check: (context) => {
      const functions = functionsByName(context);

      return rlsTables(context).flatMap((table) =>
        table.policies.flatMap((policy): FindingInput[] => {
          for (const name of policy.functions ?? []) {
            const slow = functions
              .get(name)
              ?.find((fn) => notInlinable(fn) !== undefined);

            if (!slow) {
              continue;
            }

            const column = expressions(policy)
              .flatMap((expression) => callArguments(expression, slow))
              .map((args) => columnArgument(args, table))
              .find((found) => found !== undefined);

            if (!column) {
              continue;
            }

            const fix =
              slow.securityDefiner || Object.keys(slow.settings).length > 0
                ? ""
                : `, or make it \`language sql stable\` so Postgres inlines it`;

            return [
              {
                message: `Policy "${policy.name}" on ${qualified(table)} calls ${name}(${column}), ${notInlinable(slow)}, with a column of the row, so it runs once per row. Have a helper return the allowed values once and compare: \`${column} in (select <helper>())\`${fix}.`,
                target: `${qualified(table)}.${policy.name}`,
                object: policyObject(table, policy),
              },
            ];
          }

          return [];
        }),
      );
    },
  },
  {
    code: "BS206",
    severity: "warning",
    title: "Security definer policy helper that cannot be inlined",
    description:
      "A security definer function is used in many policies. Postgres never inlines a security definer function, so a call that takes a column of the row runs once per row. Wrapped in `(select ...)` with constant arguments, or returning a set the policy compares with `in (select ...)`, it runs once per statement.",
    check: (context) => {
      const limit = context.config.doctor.policyHelperLimit;
      const functions = functionsByName(context);
      const uses = new Map<string, string[]>();

      for (const table of rlsTables(context)) {
        for (const policy of table.policies) {
          for (const name of policy.functions ?? []) {
            if (onlyWrapped(name, [policy.using, policy.check])) {
              continue;
            }

            const list = uses.get(name) ?? [];
            list.push(`${qualified(table)}.${policy.name}`);
            uses.set(name, list);
          }
        }
      }

      return [...uses].flatMap(([name, policies]): FindingInput[] => {
        if (policies.length <= limit) {
          return [];
        }

        const fn = functions
          .get(name)
          ?.find((candidate) => candidate.securityDefiner);

        if (!fn) {
          return [];
        }

        const shown = policies.slice(0, 5).join(", ");

        const more =
          policies.length > 5 ? ` and ${policies.length - 5} more` : "";

        return [
          {
            message: `${name} is a security definer ${fn.language} function used in ${policies.length} policies (${shown}${more}; the limit is ${limit}). Postgres can't inline it, so call it as \`(select ${name}(...))\` when its arguments don't come from the row, or return the allowed ids as a set and compare with \`column in (select ${name}())\`, so it runs once per statement.`,
            target: name,
            object: functionObject(fn),
          },
        ];
      });
    },
  },
  {
    code: "BS207",
    severity: "warning",
    title: "Several permissive policies for one command and role",
    description:
      "Postgres evaluates every permissive policy that applies and ORs them, so each extra policy adds its cost to every row. Merge them into one policy per command and role. On an app table a block runs over, one app policy next to the block's `bsb_<table>_<command>` policy is left to BS347. When the performance advisor (BS200) runs, splinter's `multiple_permissive_policies` reports a table it covers and this rule skips it; on a saved snapshot this rule reports every table.",
    check: async (context) => {
      const splinter = await splinterTables(
        context,
        "multiple_permissive_policies",
      );

      const paired = appAndBlockPolicy(context);

      return rlsTables(context).flatMap((table): FindingInput[] => {
        if (splinter?.has(qualified(table))) {
          return [];
        }

        const overlaps = permissiveOverlaps(table).filter(
          (overlap) => !paired(qualified(table), overlap.policies),
        );

        if (overlaps.length === 0) {
          return [];
        }

        const first = table.policies.find(
          (policy) => policy.name === overlaps[0]!.policies[0],
        )!;

        const list = overlaps
          .map(
            (overlap) =>
              `${overlap.command} for ${overlap.role}: ${overlap.policies.join(", ")}`,
          )
          .join("; ");

        return [
          {
            message: `${qualified(table)} has several permissive policies per command and role (${list}). Postgres runs all of them for every row; merge each group into one policy.`,
            target: qualified(table),
            object: policyObject(table, first),
          },
        ];
      });
    },
  },
  {
    code: "BS213",
    severity: "warning",
    title: "API roles can write the columns that grant access",
    description:
      "RLS helpers decide access from columns such as `memberships.user_id`, `memberships.role` or `contacts.customer_id`, and an authorization provider lists them as `decidingColumns`. When `anon` or `authenticated` may insert or update one of them, and a policy lets them write the row, a user can grant themselves access. A table-level grant counts even after a column-level revoke. A single-column primary key, a tenant column every write policy pins to a tenant the caller acts in (`current_tenant_id()`, `can('tenant', column, ...)`, `tenant_ids_with(...)` or the membership helper `member_organization_ids()`, alone or next to a guest's grant from `portal_subjects()`), a subject's `deletedAt` column in `config.records` and a block's soft-delete column (they only hide rows) don't count unless the provider lists them.",
    check: (context) => {
      const tables = new Map(
        catalogOf(context).tables.map((table) => [qualified(table), table]),
      );

      return [...grantColumns(context)].flatMap(
        ([name, byColumn]): FindingInput[] => {
          const table = tables.get(name);

          if (!table) {
            return [];
          }

          const columns = table.columns
            .map((column) => column.name)
            .filter((column) => byColumn.has(column))
            .toSorted();

          const deciding = new Set(
            columns.filter((column) => byColumn.get(column)!.provider),
          );

          const writes: string[] = [];
          const fix: string[] = [];

          for (const role of API_ROLES) {
            const tableLevel: string[] = [];
            const revoked = new Set<string>();

            for (const command of WRITES) {
              const writable = writableColumns(
                table,
                columns,
                command,
                role,
                deciding,
              );

              if (writable.length === 0) {
                continue;
              }

              writes.push(`${role} may ${command} ${writable.join(", ")}`);
              const privilege = command.toUpperCase();

              const grantedTable = table.grants.some(
                (grant) =>
                  grantsTo(grant, role) && grant.privileges.includes(privilege),
              );

              if (grantedTable) {
                tableLevel.push(command);

                for (const column of writable) {
                  revoked.add(column);
                }

                continue;
              }

              const fromPublic = (table.columnGrants ?? []).some(
                (grant) =>
                  grant.role === "PUBLIC" &&
                  writable.includes(grant.column) &&
                  grant.privileges.includes(privilege),
              );

              fix.push(
                `revoke ${command} (${writable.join(", ")}) on ${name} from ${fromPublic ? `${role}, public` : role};`,
              );
            }

            if (tableLevel.length === 0) {
              continue;
            }

            const fromPublic = table.grants.some(
              (grant) =>
                grant.role === "PUBLIC" &&
                tableLevel.some((command) =>
                  grant.privileges.includes(command.toUpperCase()),
                ),
            );

            fix.push(
              `revoke ${tableLevel.join(", ")} on ${name} from ${fromPublic ? `${role}, public` : role};`,
            );

            const rest = table.columns
              .map((column) => column.name)
              .filter((column) => !revoked.has(column));

            if (rest.length > 0) {
              fix.push(
                `grant ${tableLevel.map((command) => `${command} (${rest.join(", ")})`).join(", ")} on ${name} to ${role};`,
              );
            }
          }

          if (writes.length === 0) {
            return [];
          }

          const helpers = [
            ...new Set(
              columns.flatMap((column) => [...byColumn.get(column)!.helpers]),
            ),
          ].toSorted();

          const listed = [...deciding];

          const readers = [
            ...(helpers.length > 0
              ? [
                  `${helpers.join(", ")} read${helpers.length === 1 ? "s" : ""} them to decide access`,
                ]
              : []),
            ...(listed.length > 0
              ? [
                  `the authorization provider lists ${listed.join(", ")} as deciding columns`,
                ]
              : []),
          ].join(", and ");

          return [
            {
              message: `${name}: ${writes.join("; ")}. ${readers}, so a user who writes them can grant themselves access. Revoke the columns and grant the rest:\n${fix.join("\n")}`,
              target: name,
              object: tableObject(table),
            },
          ];
        },
      );
    },
  },
  {
    code: "BS211",
    severity: "info",
    title: "Statement timeouts for the Data API roles",
    description:
      "PostgREST switches to `anon` or `authenticated` for each request, so their `statement_timeout` limits Data API queries. A function's own `set statement_timeout` only applies when PostgREST hoists it (`pgrst.db_hoisted_tx_settings`). `idle_in_transaction_session_timeout` ends sessions that leave a transaction open; it applies to the role a connection logs in as.",
    check: (context) => {
      const settings = context.snapshot.extras.roleSettings;

      if (!settings) {
        return [];
      }

      const values = (setting: string): string =>
        TIMEOUT_ROLES.map(
          (role) => `${role} ${settings[role]?.[setting] ?? "not set"}`,
        ).join(", ");

      const findings: FindingInput[] = [
        {
          message: `statement_timeout: ${values("statement_timeout")}. idle_in_transaction_session_timeout: ${values("idle_in_transaction_session_timeout")}. Unset roles use the database default.`,
          target: "roles:statement_timeout",
        },
      ];

      const configured =
        settings["authenticator"]?.["pgrst.db_hoisted_tx_settings"];

      const hoisted = configured
        ? configured.split(",").map((setting) => setting.trim())
        : DEFAULT_HOISTED;

      if (hoisted.includes("statement_timeout")) {
        return findings;
      }

      for (const fn of context.snapshot.extras.functions ?? []) {
        const timeout = fn.settings["statement_timeout"];

        if (!timeout || !context.config.schemas.includes(fn.schema)) {
          continue;
        }

        findings.push({
          severity: "warning",
          message: `${functionName(fn)}(${fn.signature}) sets statement_timeout = ${timeout}, but pgrst.db_hoisted_tx_settings (${configured}) leaves it out, so the setting doesn't limit the RPC. Add statement_timeout to it, or set the timeout on the role.`,
          target: `${functionName(fn)}:statement_timeout`,
          object: functionObject(fn),
        });
      }

      return findings;
    },
  },
  {
    code: "BS224",
    severity: "warning",
    title: "Data API role without a timeout",
    description:
      "Without `statement_timeout`, one slow Data API query holds a connection until it finishes; without `idle_in_transaction_session_timeout`, a client that leaves a transaction open holds its locks. PostgREST applies the settings of `anon` and `authenticated` to each request, and the login role's (`authenticator`) apply when the request role sets none, so doctor accepts either. A value of 0 turns the timeout off and counts as unset.",
    check: (context) => {
      const settings = context.snapshot.extras.roleSettings;

      if (!settings) {
        return [];
      }

      const value = (role: string, setting: string): string | undefined => {
        const set = settings[role]?.[setting];

        return set === undefined || /^0(?:\s*m?s)?$/i.test(set.trim())
          ? undefined
          : set;
      };

      const example: Readonly<Record<string, string>> = {
        statement_timeout: "'8s'",
        idle_in_transaction_session_timeout: "'60s'",
      };

      return (["anon", "authenticated"] as const).flatMap((role) =>
        Object.keys(example)
          .filter(
            (setting) =>
              value(role, setting) === undefined &&
              value("authenticator", setting) === undefined,
          )
          .map((setting): FindingInput => ({
            message: `${role} has no ${setting}, and authenticator sets none either, so a Data API request as ${role} has no limit. Run \`alter role ${role} set ${setting} = ${example[setting]!};\` in a migration, then \`notify pgrst, 'reload config';\`.`,
            target: `${role}:${setting}`,
          })),
      );
    },
  },
];
