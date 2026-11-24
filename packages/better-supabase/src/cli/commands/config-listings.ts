import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { ShareCheck } from "../doctor/function-shares.ts";
import type { Snapshot } from "../introspect/types.ts";

import {
  FUNCTION_CALLERS,
  functionCounts,
  listAccessPolicies,
  listActions,
  listFunctions,
} from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import {
  checkShareable,
  qualifiedName,
  shareScope,
} from "../doctor/function-shares.ts";
import { toCatalog } from "../introspect/catalog.ts";
import { schemaTagComments } from "../schema-tags.ts";
import { loadSnapshot } from "./snapshot.ts";
import { SOURCE_ARGS, sourceArgs } from "./source-args.ts";

/** `public.*_payload` as a pattern over `schema.name`. */
function globPattern(glob: string): RegExp {
  const escaped = qualifiedName(glob)
    .split("*")
    .map((part) => part.replaceAll(/[$()+.?[\\\]^{|}]/gu, String.raw`\$&`))
    .join(".*");

  return new RegExp(`^${escaped}$`, "u");
}

function verdictOf(check: ShareCheck): string {
  if (check.reasons.length > 0) {
    return "can't be shared";
  }

  return check.listed || check.name.startsWith("better_supabase.")
    ? "shareable"
    : "shareable once sharedFunctions lists it";
}

function shareLines(check: ShareCheck, depth: number): string[] {
  const pad = "  ".repeat(depth);

  const facts = [
    ...(check.reads.length > 0 ? [`reads ${check.reads.join(", ")}`] : []),
    ...(check.permissions.length > 0
      ? [`filters by ${check.permissions.join(", ")}`]
      : []),
  ];

  return [
    `${pad}${check.name}: ${verdictOf(check)}${facts.length > 0 ? ` (${facts.join("; ")})` : ""}`,
    ...check.reasons.map((reason) => `${pad}  - ${reason}`),
    ...check.calls.flatMap((call) => shareLines(call, depth + 1)),
  ];
}

/**
 * `config functions --shareable`: BS430's check on functions before they are
 * listed.
 */
export async function shareableReport(
  config: ResolvedConfig,
  snapshot: Snapshot,
  glob: string,
): Promise<CommandResult> {
  const provider = config.authorization;

  if (!provider) {
    return {
      code: 1,
      errorCode: "failed",
      error:
        "The config sets no authorization provider, so no function can be shared per tenant.",
    };
  }

  const catalog = toCatalog(snapshot);
  const pattern = globPattern(glob);

  const matched = catalog.functions.filter((fn) =>
    pattern.test(`${fn.schema}.${fn.name}`),
  );

  if (matched.length === 0) {
    return {
      code: 0,
      output: `No function matches ${glob}.`,
      data: { version: 1, functions: [] },
    };
  }

  const scope = shareScope(
    provider,
    catalog.functions,
    catalog.tables,
    snapshot.extras.functionSources,
  );

  const checks = await Promise.all(
    matched.map((fn) => checkShareable(fn, scope)),
  );

  const passing = checks.filter((check) => check.reasons.length === 0).length;

  return {
    code: 0,
    output: [
      ...checks.flatMap((check) => shareLines(check, 0)),
      "",
      `${String(passing)} of ${String(checks.length)} can be shared.`,
    ].join("\n"),
    data: { version: 1, functions: checks },
  };
}

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
    shareable: {
      type: "string",
      description:
        "Check whether a share: \"tenant\" fill may call the functions that match, e.g. 'public.*_payload', with every reason and the functions they call (doctor BS430)",
      valueHint: "glob",
    },
  },
  run: async (args, { config, env, io }) => {
    const snapshot = await loadSnapshot(
      config,
      env,
      await sourceArgs(args, io),
    );

    if (args.shareable !== undefined) {
      return shareableReport(config, snapshot, args.shareable);
    }

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
