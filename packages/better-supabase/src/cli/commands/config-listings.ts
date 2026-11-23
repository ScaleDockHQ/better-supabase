import type { AnyCommand } from "../core/command.ts";

import {
  FUNCTION_CALLERS,
  functionCounts,
  listAccessPolicies,
  listActions,
  listFunctions,
} from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import { schemaTagComments } from "../schema-tags.ts";
import { loadSnapshot } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

export const configActionsCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("config actions"),
  args: {},
  run: (_args, { config }) => {
    const actions = listActions(config);

    return Promise.resolve({
      code: 0,
      output:
        actions.length === 0
          ? "No actions."
          : actions
              .map(
                (row) =>
                  `${row.kind} ${row.name} ${row.action}: ${row.key ?? "no key"} (${row.source})`,
              )
              .join("\n"),
      data: { version: 1, actions },
    });
  },
});

export const configPoliciesCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("config policies"),
  args: {},
  run: async (_args, { config }) => {
    const policies = listAccessPolicies(
      config,
      await schemaTagComments(config),
    );

    return {
      code: 0,
      output:
        policies.length === 0
          ? "No @bsb access policies."
          : policies
              .map(
                (row) =>
                  `${row.schema}.${row.table} ${row.operation}: ${row.name} requires ${row.key} on ${row.tenantColumn}${row.actorGuard ? " (actor guard)" : ""}`,
              )
              .join("\n"),
      data: { version: 1, policies },
    };
  },
});

export const configFunctionsCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("config functions"),
  args: {
    ...SOURCE_ARGS,
    all: {
      type: "boolean",
      description: "List every function, not only the counts per schema",
    },
  },
  run: async (args, { config, env, io }) => {
    const snapshot = await loadSnapshot(
      config,
      env,
      await sourceArgs(args, io),
    );

    const inventory = snapshot.extras.functionInventory;

    if (inventory === undefined) {
      return {
        code: 1,
        errorCode: "failed",
        error:
          "The snapshot has no function inventory. Read the database, or save a new snapshot with `better-supabase gen --save-snapshot`.",
      };
    }

    const functions = listFunctions(inventory);
    const counts = functionCounts(functions);

    const summary = Object.entries(counts).map(
      ([schema, row]) =>
        `${schema}: ${FUNCTION_CALLERS.map((caller) => `${String(row[caller])} ${caller}`).join(", ")}`,
    );

    return {
      code: 0,
      output:
        functions.length === 0
          ? "No functions."
          : [
              ...(args.all === true
                ? functions.map(
                    (fn) =>
                      `${fn.schema}.${fn.name}(${fn.signature}) ${fn.caller}`,
                  )
                : []),
              ...summary,
            ].join("\n"),
      data: { version: 1, counts, functions },
    };
  },
});
