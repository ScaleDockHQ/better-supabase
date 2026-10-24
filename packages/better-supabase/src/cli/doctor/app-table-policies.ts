import type { BlockSqlDeprecation } from "../../sql/index.ts";
import type { CatalogPolicy } from "../introspect/types.ts";
import type { DoctorContext, FindingInput } from "./rules.ts";

import {
  adoptedTables,
  moduleDeprecations,
  SQL_MODULES,
} from "../../sql/index.ts";
import { appTablesOf } from "./app-tables.ts";
import { BLOCK_PREFIX } from "./block-policies.ts";
import { moduleFiles } from "./module-files.ts";
import { catalogOf, qualified } from "./shared.ts";

type Command = "select" | "insert" | "update" | "delete";

const COMMANDS: readonly Command[] = ["select", "insert", "update", "delete"];

const covers = (policy: CatalogPolicy, command: Command): boolean =>
  policy.command === "all" || policy.command === command;

const normalized = (expression: string | null): string =>
  (expression ?? "").replaceAll(/\s+/g, " ").trim();

/**
 * The expressions that decide `command`: `using` reads rows, `check` writes
 * them, and an update needs both.
 */
function conditions(policy: CatalogPolicy, command: Command): string[] {
  switch (command) {
    case "select":
    case "delete": {
      return [normalized(policy.using)];
    }

    case "insert": {
      return [normalized(policy.check)];
    }

    case "update": {
      return [
        normalized(policy.using),
        normalized(policy.check ?? policy.using),
      ];
    }

    default: {
      const unhandled: never = command;

      return unhandled;
    }
  }
}

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

/** The operands of the top-level `and`s in `expression`, as Postgres prints it. */
function conjuncts(expression: string): Set<string> {
  const text = unwrapped(expression);
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
      text.slice(index, index + 5).toLowerCase() === " and "
    ) {
      parts.push(text.slice(start, index));
      start = index + 5;
      index += 4;
    }
  }

  parts.push(text.slice(start));

  return new Set(parts.map(unwrapped));
}

/**
 * Whether the block's condition for `command` is the app's with more `and`
 * operands, so it admits no row the app's policy doesn't. The same condition
 * counts.
 */
const narrows = (
  block: CatalogPolicy,
  app: CatalogPolicy,
  command: Command,
): boolean => {
  const own = conditions(app, command);

  return conditions(block, command).every((expression, index) => {
    const required = conjuncts(own[index] ?? "");
    const present = conjuncts(expression);

    return [...required].every((operand) => present.has(operand));
  });
};

const unconditional = (policy: CatalogPolicy, command: Command): boolean =>
  conditions(policy, command).every((expression) => expression === "true");

const reachesRoles = (app: CatalogPolicy, block: CatalogPolicy): boolean =>
  app.roles.includes("public") ||
  block.roles.every((role) => app.roles.includes(role));

/**
 * Block policies (`bsb_*`, permissive) on the app's tables that grant a command
 * more than the app's own permissive policies do. Postgres ORs permissive
 * policies, so a block policy whose condition no app policy repeats can open
 * rows the app's policies keep closed. A command the app has no policy for is
 * the block's to grant.
 */
export function widenedAppTablePolicies(
  context: DoctorContext,
): FindingInput[] {
  const tables = adoptedTables(context.config.blocks, appTablesOf(context));

  if (tables.length === 0) {
    return [];
  }

  const modules = new Map<string, Set<string>>();

  for (const table of tables) {
    const target = `${table.schema}.${table.table}`;
    modules.set(target, (modules.get(target) ?? new Set()).add(table.module));
  }

  return catalogOf(context).tables.flatMap((table): FindingInput[] => {
    const target = qualified(table);
    const owners = modules.get(target);

    if (owners === undefined) {
      return [];
    }

    const permissive = table.policies.filter((policy) => policy.permissive);

    const own = permissive.filter(
      (policy) => !policy.name.startsWith(BLOCK_PREFIX),
    );

    const blocks = [...owners].map((module) => `blocks.${module}`).join(" or ");

    return permissive
      .filter((policy) => policy.name.startsWith(BLOCK_PREFIX))
      .flatMap((policy): FindingInput[] => {
        const widened = COMMANDS.filter((command) => {
          if (!covers(policy, command)) {
            return false;
          }

          const apps = own.filter((app) => covers(app, command));

          return (
            apps.length > 0 &&
            !apps.some(
              (app) =>
                reachesRoles(app, policy) &&
                (unconditional(app, command) || narrows(policy, app, command)),
            )
          );
        });

        if (widened.length === 0) {
          return [];
        }

        const reason = `no policy of the app's for ${widened.join(", ")} reaches its roles with a condition it repeats (alone or with more "and" operands), so it can open rows the app's policies keep closed`;

        return [
          {
            message: `${blocks} adds policy ${policy.name} on ${target}, and ${reason}. Postgres ORs permissive policies; doctor compares conditions as text and can't prove that one implies another. If the block's condition is what the app means, repeat it in the app's policy; otherwise narrow the permission key it checks, or drop ${policy.name} in a schema file that runs after the block's.`,
            target: `${target}.${policy.name}`,
            object: {
              kind: "policy",
              schema: table.schema,
              table: table.name,
              name: policy.name,
            },
          },
        ];
      });
  });
}

const KEPT_TRIGGER =
  /^-- (\S+) keeps updated_at current with its own trigger (\S+)\.$/gm;

/**
 * App tables whose own trigger keeps `updated_at` current, so the block skipped
 * its `bsb_updated_at` trigger there.
 */
export async function keptUpdatedAtTriggers(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const states = await moduleFiles(context);

  return states.flatMap(({ file }): FindingInput[] =>
    file.kind === "schema"
      ? [...file.contents.matchAll(KEPT_TRIGGER)].map(
          ([, target = "", trigger = ""]) => {
            const dot = target.indexOf(".");

            return {
              message: `blocks.${file.instance ?? file.module} runs over ${target}, which keeps updated_at current with its own trigger ${trigger}, so the block adds no bsb_updated_at trigger there. Keep ${trigger} firing on update; if you drop it, run \`better-supabase upgrade\` to add the block's.`,
              target,
              object: {
                kind: "table",
                schema: target.slice(0, dot),
                name: target.slice(dot + 1),
              },
            };
          },
        )
      : [],
  );
}

/**
 * Whether a deprecated table or column name belongs to the app: the app's
 * tables keep the app's names, as custom blocks' tables do.
 */
export function keepsAppsName(
  context: DoctorContext,
): (entry: BlockSqlDeprecation & { readonly module: string }) => boolean {
  const named = context.config.blockNames.some((name) =>
    moduleDeprecations().some(
      (entry) =>
        entry.module === name &&
        (entry.kind === "table" || entry.kind === "column"),
    ),
  );

  const adopted = named
    ? adoptedTables(context.config.blocks, appTablesOf(context))
    : [];

  return (entry) => {
    if (entry.kind !== "table" && entry.kind !== "column") {
      return false;
    }

    if (
      (context.config.blocks[entry.module]?.mode ?? "managed") !== "managed"
    ) {
      return true;
    }

    const name =
      entry.kind === "table"
        ? entry.symbol.slice(entry.symbol.lastIndexOf(".") + 1)
        : entry.symbol.slice(0, entry.symbol.indexOf("."));

    return adopted.some(
      (table) =>
        table.module === entry.module &&
        (name === table.logical ||
          name === table.table ||
          name ===
            SQL_MODULES[table.module]?.names?.tables[table.logical]?.name),
    );
  };
}
