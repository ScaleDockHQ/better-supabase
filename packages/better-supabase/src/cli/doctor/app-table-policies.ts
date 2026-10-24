import type { BlockSqlDeprecation } from "../../sql/index.ts";
import type { CatalogPolicy } from "../introspect/types.ts";
import type { DoctorContext, FindingInput } from "./rules.ts";

import {
  adoptedTables,
  moduleDeprecations,
  SQL_MODULES,
} from "../../sql/index.ts";
import { appTablesOf } from "./app-tables.ts";
import { moduleFiles } from "./module-files.ts";
import { catalogOf, qualified } from "./shared.ts";

/** The prefix the render pass gives block policies on the app's tables. */
const BLOCK_PREFIX = "bsb_";

type Command = "select" | "insert" | "update" | "delete";

const COMMANDS: readonly Command[] = ["select", "insert", "update", "delete"];

const covers = (policy: CatalogPolicy, command: Command): boolean =>
  policy.command === "all" || policy.command === command;

const normalized = (expression: string | null): string =>
  (expression ?? "").replaceAll(/\s+/g, " ").trim();

/**
 * The expressions that decide `command`: `using` reads rows, `check` writes
 * them.
 */
function condition(policy: CatalogPolicy, command: Command): string {
  switch (command) {
    case "select":
    case "delete": {
      return normalized(policy.using);
    }

    case "insert": {
      return normalized(policy.check);
    }

    case "update": {
      return `${normalized(policy.using)} | ${normalized(policy.check ?? policy.using)}`;
    }

    default: {
      const unhandled: never = command;

      return unhandled;
    }
  }
}

const unconditional = (policy: CatalogPolicy, command: Command): boolean =>
  command === "update"
    ? normalized(policy.using) === "true" &&
      normalized(policy.check ?? policy.using) === "true"
    : condition(policy, command) === "true";

const reachesRoles = (app: CatalogPolicy, block: CatalogPolicy): boolean =>
  app.roles.includes("public") ||
  block.roles.every((role) => app.roles.includes(role));

/**
 * Block policies (`bsb_*`, permissive) on the app's tables that grant a command
 * more than the app's own permissive policies do. Postgres ORs permissive
 * policies, so a block policy whose condition no app policy repeats can open
 * rows the app's policies keep closed.
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

          return !own.some(
            (app) =>
              covers(app, command) &&
              reachesRoles(app, policy) &&
              (unconditional(app, command) ||
                condition(app, command) === condition(policy, command)),
          );
        });

        if (widened.length === 0) {
          return [];
        }

        const unguarded = widened.filter(
          (command) => !own.some((app) => covers(app, command)),
        );

        const reason =
          unguarded.length === widened.length
            ? `the app has no policy of its own for ${widened.join(", ")}, so this one grants it alone`
            : `no policy of the app's for ${widened.join(", ")} has the same condition and roles, so it can open rows the app's policies keep closed`;

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
