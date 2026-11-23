import type { AnyCommand } from "../core/command.ts";

import { listAccessPolicies, listActions } from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import { schemaTagComments } from "../schema-tags.ts";

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
