import type { CatalogPolicy } from "../config/snapshot.ts";

import { maskComments, statementSpans } from "./over-app-tables.ts";
import { catalogPolicy, readPolicy } from "./policy.ts";
import { qualified, unquote, NAME } from "./schema-scan.ts";

export type PolicyCommand = "select" | "insert" | "update" | "delete";

const COMMANDS: readonly PolicyCommand[] = [
  "select",
  "insert",
  "update",
  "delete",
];

/** Whether `policy` applies to `command`. */
const coversCommand = (
  policy: CatalogPolicy,
  command: PolicyCommand,
): boolean => policy.command === "all" || policy.command === command;

/** Whether the parentheses that open `text` close at its last character. */
function enclosed(text: string): boolean {
  if (!(text.startsWith("(") && text.endsWith(")"))) {
    return false;
  }

  let depth = 0;
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (char === "'") {
      quoted = !quoted;
    } else if (!quoted && char === "(") {
      depth += 1;
    } else if (!quoted && char === ")") {
      depth -= 1;

      if (depth === 0 && index < text.length - 1) {
        return false;
      }
    }
  }

  return true;
}

const unwrapped = (expression: string): string => {
  let text = expression.trim();

  while (enclosed(text)) {
    text = text.slice(1, -1).trim();
  }

  return text;
};

const SIMPLE_IDENT = /^[a-z_][a-z0-9_$]*$/;

const SELECT_ALIAS = /\)\s+as\s+[a-z_][a-z0-9_$]*$/;

/**
 * `text` in one spelling for the ways a schema file and Postgres write the same
 * condition: keywords and names lowercased outside string literals, simple
 * names unquoted, whitespace collapsed, no space inside parentheses, no outer
 * parentheses, and no alias Postgres adds to a call in a sub-select (`select
 * f() as f`).
 */
export function canonicalCondition(text: string): string {
  let out = "";
  const selects: boolean[] = [];

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]!;

    if (char === "'") {
      let end = index + 1;

      while (end < text.length) {
        if (text[end] === "'" && text[end + 1] === "'") {
          end += 2;
        } else if (text[end] === "'") {
          break;
        } else {
          end += 1;
        }
      }

      out += text.slice(index, end + 1);
      index = end;
      continue;
    }

    if (char === '"') {
      const end = text.indexOf('"', index + 1);
      const name = text.slice(index + 1, end === -1 ? text.length : end);

      out += SIMPLE_IDENT.test(name) ? name : `"${name}"`;
      index = end === -1 ? text.length : end;
      continue;
    }

    if (/\s/.test(char)) {
      if (!out.endsWith(" ") && !out.endsWith("(")) {
        out += " ";
      }

      continue;
    }

    if (char === "(") {
      out += "(";
      selects.push(/^\s*select\b/i.test(text.slice(index + 1)));
      continue;
    }

    if (char === ")") {
      out = out.trimEnd();

      if (selects.pop() === true) {
        out = out.replace(SELECT_ALIAS, ")");
      }

      out += ")";
      continue;
    }

    out += char.toLowerCase();
  }

  return unwrapped(out.trim());
}

/**
 * The expressions that decide `command`: `using` reads rows, `check` writes
 * them, and an update needs both.
 */
function conditions(policy: CatalogPolicy, command: PolicyCommand): string[] {
  switch (command) {
    case "select":
    case "delete": {
      return [canonicalCondition(policy.using ?? "")];
    }

    case "insert": {
      return [canonicalCondition(policy.check ?? "")];
    }

    case "update": {
      return [
        canonicalCondition(policy.using ?? ""),
        canonicalCondition(policy.check ?? policy.using ?? ""),
      ];
    }

    default: {
      const unhandled: never = command;

      return unhandled;
    }
  }
}

/** The operands of the top-level `and`s or `or`s in `expression`. */
function operands(expression: string, operator: "and" | "or"): string[] {
  const text = unwrapped(expression);
  const separator = ` ${operator} `;
  const parts: string[] = [];
  let depth = 0;
  let quoted = false;
  let start = 0;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (char === "'") {
      quoted = !quoted;
    } else if (!quoted && char === "(") {
      depth += 1;
    } else if (!quoted && char === ")") {
      depth -= 1;
    } else if (
      !quoted &&
      depth === 0 &&
      text.slice(index, index + separator.length).toLowerCase() === separator
    ) {
      parts.push(text.slice(start, index));
      start = index + separator.length;
      index += separator.length - 1;
    }
  }

  parts.push(text.slice(start));

  return parts.map(unwrapped);
}

/** Whether every `and` operand of `required` is one of `present`'s. */
const implied = (required: string, present: ReadonlySet<string>): boolean =>
  operands(required, "and").every((operand) => present.has(operand));

/**
 * Whether the block's condition for `command` admits no row the app's policy
 * doesn't: it repeats the app's condition, or one of its top-level `or`
 * operands, alone or with more `and` operands.
 */
const narrows = (
  block: CatalogPolicy,
  app: CatalogPolicy,
  command: PolicyCommand,
): boolean => {
  const own = conditions(app, command);

  return conditions(block, command).every((expression, index) => {
    const required = own[index] ?? "";
    const present = new Set(operands(expression, "and"));

    return (
      implied(required, present) ||
      operands(required, "or").some((operand) => implied(operand, present))
    );
  });
};

const unconditional = (
  policy: CatalogPolicy,
  command: PolicyCommand,
): boolean =>
  conditions(policy, command).every((expression) => expression === "true");

const reachesRoles = (app: CatalogPolicy, block: CatalogPolicy): boolean =>
  app.roles.includes("public") ||
  block.roles.every((role) => app.roles.includes(role));

/**
 * The app's permissive policy that already allows what `block` allows for
 * `command`: it reaches the block's roles with `true` or a condition (or one of
 * its top-level `or` operands) the block's repeats, alone or with more `and`
 * operands.
 */
function coveringPolicy(
  block: CatalogPolicy,
  apps: readonly CatalogPolicy[],
  command: PolicyCommand,
): CatalogPolicy | undefined {
  return apps.find(
    (app) =>
      app.permissive &&
      coversCommand(app, command) &&
      reachesRoles(app, block) &&
      (unconditional(app, command) || narrows(block, app, command)),
  );
}

/**
 * The commands `block` grants beyond the app's permissive policies: the app has
 * a policy for the command and none of them covers the block's. A command the
 * app has no policy for is the block's to grant.
 */
export function widenedCommands(
  block: CatalogPolicy,
  apps: readonly CatalogPolicy[],
): PolicyCommand[] {
  return COMMANDS.filter(
    (command) =>
      coversCommand(block, command) &&
      apps.some((app) => app.permissive && coversCommand(app, command)) &&
      coveringPolicy(block, apps, command) === undefined,
  );
}

/**
 * The policy a `create policy` statement creates, with its table as
 * `schema.table`; `undefined` for any other statement.
 */
export function parsePolicy(
  statement: string,
): { readonly table: string; readonly policy: CatalogPolicy } | undefined {
  const read = readPolicy(statement);

  return read === undefined
    ? undefined
    : { table: read.table, policy: catalogPolicy(read) };
}

const BLOCK_PREFIX = "bsb_";

const POLICY_EDIT = new RegExp(
  String.raw`^\s*(?:alter\s+policy|comment\s+on\s+policy)\s+(${NAME})\s+on\s+(${NAME}(?:\s*\.\s*${NAME})?)`,
  "i",
);

type BlockPolicy = NonNullable<ReturnType<typeof parsePolicy>>;

function withoutBlockPolicies(
  sql: string,
  skip: (parsed: BlockPolicy) => string | undefined,
  restrictive = false,
): string {
  const masked = maskComments(sql);
  const skipped = new Set<string>();

  const statements = statementSpans(sql).map(([from, to]) => ({
    text: sql.slice(from, to),
    masked: masked.slice(from, to),
  }));

  const kept = statements.map(({ text, masked: statement }) => {
    const parsed = parsePolicy(statement);

    if (
      parsed === undefined ||
      !parsed.policy.name.startsWith(BLOCK_PREFIX) ||
      !(parsed.policy.permissive || restrictive)
    ) {
      return text;
    }

    const comment = skip(parsed);

    if (comment === undefined) {
      return text;
    }

    skipped.add(`${parsed.table}\u0000${parsed.policy.name}`);

    const start = statement.search(/\S/);
    const lead = text.slice(0, start === -1 ? 0 : start).trimEnd();

    return `${lead}\n-- ${parsed.table}: ${comment}`;
  });

  return statements
    .map(({ masked: statement }, index) => {
      const edit = POLICY_EDIT.exec(statement);

      return edit !== null &&
        skipped.has(`${qualified(edit[2]!)}\u0000${unquote(edit[1]!)}`)
        ? ""
        : kept[index]!;
    })
    .join("");
}

/**
 * `sql` without the block's permissive `bsb_` policies that the app's own
 * policies on the same table already cover for every command they grant (the
 * comparison BS347 makes), so Postgres doesn't OR two policies that admit the
 * same rows. A block policy that is wider stays, and BS347 reports it. The
 * `drop policy if exists` before it stays too, so an earlier install's copy
 * goes.
 */
export function withoutCoveredPolicies(
  sql: string,
  ownPolicies: Readonly<Record<string, readonly CatalogPolicy[]>> = {},
): string {
  if (Object.keys(ownPolicies).length === 0) {
    return sql;
  }

  return withoutBlockPolicies(sql, ({ table, policy }) => {
    const apps = (ownPolicies[table] ?? []).filter(
      (own) => !own.name.startsWith(BLOCK_PREFIX),
    );

    const covering = COMMANDS.filter((command) =>
      coversCommand(policy, command),
    ).map((command) => coveringPolicy(policy, apps, command));

    if (covering.length === 0 || covering.includes(undefined)) {
      return;
    }

    const names = [...new Set(covering.map((own) => own!.name))].join(" and ");

    return `the app's policy ${names} already allows what ${policy.name} would, so the block adds none.`;
  });
}

const APP_POLICIES_NOTE = `the app's policies govern this table (ownTablePolicies "app"), so the block adds no`;

const APP_POLICIES = new RegExp(
  String.raw`^-- (\S+): ${APP_POLICIES_NOTE.replaceAll(/[()]/g, String.raw`\$&`)} (\S+) for ([a-z, ]+)\.$`,
  "gm",
);

export function appTablePolicyNotes(
  sql: string,
): {
  readonly table: string;
  readonly policy: string;
  readonly commands: readonly PolicyCommand[];
}[] {
  return [...sql.matchAll(APP_POLICIES)].map(
    ([, table = "", policy = "", commands = ""]) => ({
      table,
      policy,
      commands: COMMANDS.filter((command) =>
        commands.split(", ").includes(command),
      ),
    }),
  );
}

export function withoutAppTablePolicies(
  sql: string,
  tables: ReadonlySet<string>,
): string {
  if (tables.size === 0) {
    return sql;
  }

  return withoutBlockPolicies(
    sql,
    ({ table, policy }) => {
      if (!tables.has(table)) {
        return;
      }

      return policy.permissive
        ? `${APP_POLICIES_NOTE} ${policy.name} for ${COMMANDS.filter(
            (command) => coversCommand(policy, command),
          ).join(", ")}.`
        : `${APP_POLICIES_NOTE} restrictive ${policy.name}.`;
    },
    true,
  );
}

const DROP_POLICY = new RegExp(
  String.raw`^\s*drop\s+policy\s+(?:if\s+exists\s+)?(${NAME})\s+on\s+(${NAME}(?:\s*\.\s*${NAME})?)`,
  "i",
);

/**
 * The policies `sources` leave on each `schema.table` in `schemas`, in order: a
 * later `drop policy` removes one, and a later `create policy` of the same name
 * replaces it.
 */
export function declaredPolicies(
  sources: readonly { readonly text: string }[],
  schemas: readonly string[],
): Record<string, CatalogPolicy[]> {
  const found = new Map<string, Map<string, CatalogPolicy>>();

  for (const source of sources) {
    const masked = maskComments(source.text);

    for (const [from, to] of statementSpans(masked)) {
      const statement = masked.slice(from, to);
      const parsed = parsePolicy(statement);

      if (parsed !== undefined) {
        if (
          schemas.includes(parsed.table.slice(0, parsed.table.indexOf(".")))
        ) {
          const named =
            found.get(parsed.table) ?? new Map<string, CatalogPolicy>();

          named.set(parsed.policy.name, parsed.policy);
          found.set(parsed.table, named);
        }

        continue;
      }

      const drop = DROP_POLICY.exec(statement);

      if (drop !== null) {
        found.get(qualified(drop[2]!))?.delete(unquote(drop[1]!));
      }
    }
  }

  return Object.fromEntries(
    [...found].map(([table, named]) => [table, [...named.values()]]),
  );
}
