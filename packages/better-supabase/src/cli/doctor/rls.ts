import type {
  CatalogPolicy,
  CatalogTable,
  ExtrasFunction,
} from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule, SqlObject } from "./rules.ts";

import { exposed, policyObject, qualified } from "./shared.ts";

const escape = (name: string): string =>
  name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** `'it''s'` and other string literals, blanked so their text can't match. */
const withoutStrings = (text: string): string =>
  text.replace(/'(?:[^']|'')*'/g, "''");

const functionName = (fn: Pick<ExtrasFunction, "schema" | "name">): string =>
  `${fn.schema}.${fn.name}`;

const functionObject = (fn: ExtrasFunction): SqlObject => ({
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
    if (list) list.push(fn);
    else map.set(key, [fn]);
  }
  return map;
}

/** Argument lists of every call to `schema.name(...)` in an expression. */
function callArguments(
  expression: string | null,
  fn: Pick<ExtrasFunction, "schema" | "name">,
): string[] {
  if (!expression) return [];
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
      if (text[end] === "(") depth += 1;
      else if (text[end] === ")") depth -= 1;
      end += 1;
    }
    calls.push(text.slice(start, end - 1));
  }
  return calls;
}

/** The first column of `table` an argument list refers to, bare or as `table.column`. */
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

const inlinable = (fn: ExtrasFunction): boolean =>
  fn.language === "sql" && fn.volatility !== "volatile";

const rlsTables = (context: DoctorContext): CatalogTable[] =>
  exposed(context).filter((table) => table.rls);

const COMMANDS = ["select", "insert", "update", "delete"] as const;

/** Policies apply to every role when they list `public` or none. */
const appliesTo = (policy: CatalogPolicy, role: string): boolean =>
  policy.roles.length === 0 ||
  policy.roles.includes("public") ||
  policy.roles.includes(role);

export interface PermissiveOverlap {
  readonly command: (typeof COMMANDS)[number];
  readonly role: string;
  readonly policies: readonly string[];
}

/** Commands and roles that more than one permissive policy of the table covers. */
export function permissiveOverlaps(table: CatalogTable): PermissiveOverlap[] {
  const permissive = table.policies.filter((policy) => policy.permissive);
  const roles = new Set<string>();
  for (const policy of permissive) {
    const named = policy.roles.filter((role) => role !== "public");
    if (named.length < policy.roles.length || policy.roles.length === 0) {
      roles.add("anon");
      roles.add("authenticated");
    }
    for (const role of named) roles.add(role);
  }
  const overlaps: PermissiveOverlap[] = [];
  for (const command of COMMANDS) {
    for (const role of [...roles].sort()) {
      const policies = permissive
        .filter(
          (policy) =>
            (policy.command === "all" || policy.command === command) &&
            appliesTo(policy, role),
        )
        .map((policy) => policy.name);
      if (policies.length > 1) overlaps.push({ command, role, policies });
    }
  }
  return overlaps;
}

/** PostgREST's default for `db-hoisted-tx-settings`. */
const DEFAULT_HOISTED = [
  "statement_timeout",
  "plan_filter.statement_cost_limit",
  "default_transaction_isolation",
];

const TIMEOUT_ROLES = ["anon", "authenticated", "authenticator"] as const;

export const RLS_RULES: readonly Rule[] = [
  {
    code: "BS205",
    severity: "warning",
    title: "Policy calls a slow function once per row",
    description:
      "A policy passes a column of the row to a plpgsql or volatile function. Postgres cannot inline it or cache the result, so it runs once for every row the query reads.",
    check: (context) => {
      const functions = functionsByName(context);
      return rlsTables(context).flatMap((table) =>
        table.policies.flatMap((policy): FindingInput[] => {
          for (const name of policy.functions ?? []) {
            const slow = functions.get(name)?.find((fn) => !inlinable(fn));
            if (!slow) continue;
            const column = expressions(policy)
              .flatMap((expression) => callArguments(expression, slow))
              .map((args) => columnArgument(args, table))
              .find((found) => found !== undefined);
            if (!column) continue;
            const kind = slow.language === "sql" ? "volatile" : slow.language;
            return [
              {
                message: `Policy "${policy.name}" on ${qualified(table)} calls ${name}(${column}), a ${kind} function, with a column of the row, so it runs once per row and can't be inlined. Make it \`language sql stable\`, or have a helper return the allowed values once and compare: \`${column} in (select <helper>())\`.`,
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
      "A security definer function is used in many policies and is not `language sql stable`. Every query on those tables pays for the call; wrapped in `(select ...)` it runs once per statement.",
    check: (context) => {
      const limit = context.config.doctor.policyHelperLimit;
      const functions = functionsByName(context);
      const uses = new Map<string, string[]>();
      for (const table of rlsTables(context)) {
        for (const policy of table.policies) {
          for (const name of policy.functions ?? []) {
            const list = uses.get(name) ?? [];
            list.push(`${qualified(table)}.${policy.name}`);
            uses.set(name, list);
          }
        }
      }
      return [...uses].flatMap(([name, policies]): FindingInput[] => {
        if (policies.length <= limit) return [];
        const fn = functions
          .get(name)
          ?.find(
            (candidate) => candidate.securityDefiner && !inlinable(candidate),
          );
        if (!fn) return [];
        const shown = policies.slice(0, 5).join(", ");
        const more =
          policies.length > 5 ? ` and ${policies.length - 5} more` : "";
        return [
          {
            message: `${name} is a security definer ${fn.language} function used in ${policies.length} policies (${shown}${more}; the limit is ${limit}). Make it \`language sql stable\` and call it as \`(select ${name}())\` so Postgres evaluates it once per statement.`,
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
      "Postgres evaluates every permissive policy that applies and ORs them, so each extra policy adds its cost to every row. Merge them into one policy per command and role. This replaces splinter's `multiple_permissive_policies` lint for the same table.",
    check: (context) =>
      rlsTables(context).flatMap((table): FindingInput[] => {
        const overlaps = permissiveOverlaps(table);
        if (overlaps.length === 0) return [];
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
      }),
  },
  {
    code: "BS211",
    severity: "info",
    title: "Statement timeouts for the Data API roles",
    description:
      "PostgREST switches to `anon` or `authenticated` for each request, so their `statement_timeout` limits Data API queries. A function's own `set statement_timeout` only applies when PostgREST hoists it (`pgrst.db_hoisted_tx_settings`).",
    check: (context) => {
      const settings = context.snapshot.extras.roleSettings;
      if (!settings) return [];
      const timeouts = TIMEOUT_ROLES.map(
        (role) =>
          `${role} ${settings[role]?.["statement_timeout"] ?? "not set"}`,
      ).join(", ");
      const findings: FindingInput[] = [
        {
          message: `statement_timeout: ${timeouts}. Unset roles use the database default.`,
          target: "roles:statement_timeout",
        },
      ];
      const configured =
        settings["authenticator"]?.["pgrst.db_hoisted_tx_settings"];
      const hoisted = configured
        ? configured.split(",").map((setting) => setting.trim())
        : DEFAULT_HOISTED;
      if (hoisted.includes("statement_timeout")) return findings;
      for (const fn of context.snapshot.extras.functions ?? []) {
        const timeout = fn.settings["statement_timeout"];
        if (!timeout || !context.config.schemas.includes(fn.schema)) continue;
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
];
