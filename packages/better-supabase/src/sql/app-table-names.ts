import { sqlIdent } from "../core/template.ts";
import { maskComments, statementSpans } from "./over-app-tables.ts";
import { NAME, qualified, unquote } from "./schema-scan.ts";
import { shortHash } from "./shared.ts";

const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

const CREATE_POLICY = new RegExp(
  String.raw`^(\s*create\s+policy\s+)(${NAME})(\s+on\s+)(${TABLE_NAME})`,
  "id",
);

const POLICY_REFERENCE = new RegExp(
  String.raw`^(\s*(?:drop\s+policy\s+(?:if\s+exists\s+)?|alter\s+policy\s+|comment\s+on\s+policy\s+))(${NAME})(\s+on\s+)(${TABLE_NAME})`,
  "id",
);

const COMMAND = /\bfor\s+(all|select|insert|update|delete)\b/i;

const CREATE_TRIGGER = new RegExp(
  String.raw`^(\s*create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+)(${NAME})(\s[\s\S]*?\bon\s+)(${TABLE_NAME})`,
  "id",
);

const TRIGGER_REFERENCE = new RegExp(
  String.raw`^(\s*(?:drop\s+trigger\s+(?:if\s+exists\s+)?|alter\s+trigger\s+|comment\s+on\s+trigger\s+))(${NAME})(\s+on\s+)(${TABLE_NAME})`,
  "id",
);

const TABLE_TRIGGER = new RegExp(
  String.raw`^(\s*alter\s+table\s+(?:only\s+)?)(${TABLE_NAME})(\s+(?:enable|disable)\s+(?:always\s+|replica\s+)?trigger\s+)(${NAME})`,
  "id",
);

const SETS_UPDATED_AT =
  /\bexecute\s+(?:function|procedure)\s+better_supabase\.set_updated_at\s*\(/i;

/** The prefix of every policy and trigger a block names on the app's table. */
export const BLOCK_PREFIX = "bsb_";

const MAX_NAME = 63;

function fit(name: string): string {
  return name.length <= MAX_NAME
    ? name
    : `${name.slice(0, MAX_NAME - 9)}_${shortHash(name)}`;
}

const isBlockName = (name: string): boolean =>
  unquote(name).startsWith(BLOCK_PREFIX);

/** `bsb_<name>` for a trigger the block adds to the app's table. */
export const blockTriggerName = (name: string): string =>
  fit(`${BLOCK_PREFIX}${name}`);

/**
 * The names the block's policies take on the app's table:
 * `bsb_<table>_<command>`, as the app table enrich step names them, with the
 * rest of the block's own name after it when the block has more than one for
 * the command.
 */
export function blockPolicyNames(
  table: string,
  policies: readonly { readonly name: string; readonly command: string }[],
): ReadonlyMap<string, string> {
  const names = new Map<string, string>();

  for (const { name, command } of policies) {
    const base = `${BLOCK_PREFIX}${table}_${command}`;
    const same = policies.filter((policy) => policy.command === command);

    if (same.length === 1) {
      names.set(name, fit(base));
      continue;
    }

    const rest = name
      .replace(new RegExp(`^${table}_`), "")
      .replace(new RegExp(`(?:^|_)${command}(?:_|$)`), "_")
      .replaceAll(/^_+|_+$/g, "");

    names.set(
      name,
      fit(rest === "" ? `${base}_${shortHash(name)}` : `${base}_${rest}`),
    );
  }

  return names;
}

/** `text` with the match's group `group` replaced by `name`. */
function renamed(
  text: string,
  match: RegExpExecArray,
  group: number,
  name: string,
): string {
  const [from, to] = match.indices![group]!;

  const ident = /^[a-z_][a-z0-9_$]*$/.test(name) ? name : sqlIdent(name);

  return `${text.slice(0, from)}${ident}${text.slice(to)}`;
}

/** What precedes the statement in `text`: its comments and blank lines. */
function leading(text: string, match: RegExpExecArray): string {
  const [, start] = match.indices![1]!;
  const statement = match[1]!.trimStart();

  return text.slice(0, start - statement.length).trimEnd();
}

interface Parsed {
  readonly text: string;
  readonly masked: string;
}

function policiesOn(
  statements: readonly Parsed[],
  appTables: ReadonlySet<string>,
): ReadonlyMap<string, ReadonlyMap<string, string>> {
  const found = new Map<string, { name: string; command: string }[]>();

  for (const { masked } of statements) {
    const match = CREATE_POLICY.exec(masked);

    if (match === null || isBlockName(match[2]!)) {
      continue;
    }

    const table = qualified(match[4]!);

    if (!appTables.has(table)) {
      continue;
    }

    const command = COMMAND.exec(masked)?.[1]?.toLowerCase() ?? "all";
    const list = found.get(table) ?? [];

    if (!list.some((entry) => entry.name === unquote(match[2]!))) {
      list.push({ name: unquote(match[2]!), command });
    }

    found.set(table, list);
  }

  return new Map(
    [...found].map(([table, list]) => [
      table,
      blockPolicyNames(table.slice(table.indexOf(".") + 1), list),
    ]),
  );
}

/**
 * `sql` with the block's policies and triggers on the app's tables renamed with
 * the `bsb_` prefix, so a block never replaces or drops one the app wrote.
 * Dropping a policy the block doesn't create there is left out for the same
 * reason. The block's `updated_at` trigger is left out on a table whose own
 * trigger already keeps the column current (`updatedAtTriggers`).
 */
export function blockNamesOnAppTables(
  sql: string,
  appTables: ReadonlySet<string>,
  updatedAtTriggers: Readonly<Record<string, string>> = {},
): string {
  if (appTables.size === 0) {
    return sql;
  }

  const masked = maskComments(sql);

  const statements = statementSpans(sql).map(([from, to]) => ({
    text: sql.slice(from, to),
    masked: masked.slice(from, to),
  }));

  const policies = policiesOn(statements, appTables);

  return statements
    .map(({ text, masked: statement }) => {
      const create = CREATE_POLICY.exec(statement);

      if (create !== null) {
        const name = policies
          .get(qualified(create[4]!))
          ?.get(unquote(create[2]!));

        return name === undefined || isBlockName(create[2]!)
          ? text
          : renamed(text, create, 2, name);
      }

      const policy = POLICY_REFERENCE.exec(statement);

      if (policy !== null && !isBlockName(policy[2]!)) {
        const table = qualified(policy[4]!);

        if (!appTables.has(table)) {
          return text;
        }

        const name = policies.get(table)?.get(unquote(policy[2]!));

        return name === undefined
          ? leading(text, policy)
          : renamed(text, policy, 2, name);
      }

      const trigger = CREATE_TRIGGER.exec(statement);

      if (trigger !== null && appTables.has(qualified(trigger[4]!))) {
        const kept = updatedAtTriggers[qualified(trigger[4]!)];

        if (kept !== undefined && SETS_UPDATED_AT.test(statement)) {
          return `${leading(text, trigger)}
-- ${qualified(trigger[4]!)} keeps updated_at current with its own trigger ${kept}.`;
        }

        return isBlockName(trigger[2]!)
          ? text
          : renamed(text, trigger, 2, blockTriggerName(unquote(trigger[2]!)));
      }

      const reference = TRIGGER_REFERENCE.exec(statement);

      if (
        reference !== null &&
        appTables.has(qualified(reference[4]!)) &&
        !isBlockName(reference[2]!)
      ) {
        return renamed(
          text,
          reference,
          2,
          blockTriggerName(unquote(reference[2]!)),
        );
      }

      const toggle = TABLE_TRIGGER.exec(statement);

      if (
        toggle !== null &&
        appTables.has(qualified(toggle[2]!)) &&
        !isBlockName(toggle[4]!)
      ) {
        return renamed(text, toggle, 4, blockTriggerName(unquote(toggle[4]!)));
      }

      return text;
    })
    .join("");
}
