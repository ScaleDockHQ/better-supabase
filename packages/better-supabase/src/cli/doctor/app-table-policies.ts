import type { BlockSqlDeprecation } from "../../sql/index.ts";
import type { DoctorContext, FindingInput } from "./rules.ts";

import {
  adoptedTables,
  moduleDeprecations,
  SQL_MODULES,
  widenedCommands,
} from "../../sql/index.ts";
import { appTablesOf } from "./app-tables.ts";
import { BLOCK_PREFIX } from "./block-policies.ts";
import { moduleFiles } from "./module-files.ts";
import { catalogOf, qualified } from "./shared.ts";

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
    if (context.config.blocks[table.module]?.ownTablePolicies === "app") {
      continue;
    }

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
        const widened = widenedCommands(policy, own);

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

const APP_POLICIES =
  /^-- (\S+): the app's policies govern this table \(ownTablePolicies "app"\), so the block adds no (\S+) for ([a-z, ]+)\.$/gm;

export async function appTablesWithoutPolicies(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const states = await moduleFiles(context);

  const left = new Map<
    string,
    { readonly blocks: Set<string>; readonly commands: Set<string> }
  >();

  for (const { file } of states) {
    if (file.kind !== "schema") {
      continue;
    }

    for (const [, target = "", , commands = ""] of file.contents.matchAll(
      APP_POLICIES,
    )) {
      const entry = left.get(target) ?? {
        blocks: new Set<string>(),
        commands: new Set<string>(),
      };

      entry.blocks.add(`blocks.${file.instance ?? file.module}`);

      for (const command of commands.split(", ")) {
        entry.commands.add(command);
      }

      left.set(target, entry);
    }
  }

  if (left.size === 0) {
    return [];
  }

  return catalogOf(context).tables.flatMap((table): FindingInput[] => {
    const target = qualified(table);
    const entry = left.get(target);

    if (entry === undefined || !table.rls) {
      return [];
    }

    const missing = [...entry.commands].filter(
      (command) =>
        !table.policies.some(
          (policy) =>
            policy.permissive &&
            (policy.command === "all" || policy.command === command),
        ),
    );

    if (missing.length === 0) {
      return [];
    }

    const blocks = [...entry.blocks].join(" and ");

    return [
      {
        message: `${blocks} leaves the policies on ${target} to the app's (ownTablePolicies "app"), and ${target} has row level security on but no permissive policy for ${missing.join(", ")}, which the block's own policies would have granted. Postgres then denies those commands to every caller, so the block's functions that run as the caller and its TypeScript API find no rows for them. Add the app's policy for each command the app uses, or set ownTablePolicies to "block" for this block.`,
        target,
        object: { kind: "table", schema: table.schema, name: table.name },
      },
    ];
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
