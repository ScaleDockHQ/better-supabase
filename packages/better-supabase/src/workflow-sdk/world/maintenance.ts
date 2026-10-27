import type {
  OpenWorkflowHook,
  WorkflowMaintenance,
  WorkflowTerminalStatus,
} from "../run-keys.ts";

import { optionalTemporal, TEMPORAL_MISSING } from "../../core/temporal.ts";

type Call = <T>(fn: string, args: readonly unknown[]) => Promise<T[]>;

const TERMINAL: readonly WorkflowTerminalStatus[] = [
  "completed",
  "failed",
  "cancelled",
];

interface HookRow {
  readonly hook_id: string;
  readonly run_id: string;
  readonly workflow: string;
  readonly tenant_id: string | null;
  readonly actor_id: string | null;
  readonly metadata: unknown;
  readonly created_at: Date | string;
}

function instantOf(value: Date | string): Temporal.Instant {
  const namespace = optionalTemporal();

  if (namespace === undefined) {
    throw new TypeError(TEMPORAL_MISSING);
  }

  return namespace.Instant.fromEpochMilliseconds(
    (value instanceof Date ? value : new Date(value)).getTime(),
  );
}

function hookOf(row: HookRow): OpenWorkflowHook {
  return {
    hookId: row.hook_id,
    runId: row.run_id,
    workflowName: row.workflow,
    tenantId: row.tenant_id ?? undefined,
    actorId: row.actor_id ?? undefined,
    metadata: row.metadata,
    createdAt: instantOf(row.created_at),
  };
}

/** The run keys, purge and open hooks of the World, over its pool. */
export function createMaintenance(call: Call): WorkflowMaintenance {
  return {
    runKeys: {
      async claim(key) {
        const [row] = await call<{ claimed: boolean; run_id: string | null }>(
          "workflow_claim_run_key",
          [key, "5 minutes"],
        );

        return {
          claimed: row?.claimed === true,
          runId: row?.run_id ?? undefined,
        };
      },
      async set(key, runId) {
        await call("workflow_set_run_key", [key, runId]);
      },
      async release(key) {
        await call("workflow_release_run_key", [key]);
      },
    },
    async purgeRuns(options = {}) {
      const statuses = options.statuses ?? TERMINAL;
      const batch = Math.max(1, Math.trunc(options.batch ?? 500));
      let total = 0;

      for (;;) {
        const [row] = await call<{ workflow_purge_runs: number }>(
          "workflow_purge_runs",
          [options.olderThan ?? "30 days", [...statuses], batch],
        );

        const deleted = row?.workflow_purge_runs ?? 0;

        total += deleted;

        if (deleted < batch) {
          return total;
        }
      }
    },
    async openHooks(options = {}) {
      const rows = await call<HookRow>("workflow_open_hooks", [
        options.tenantId ?? null,
        options.workflowName ?? null,
        options.limit ?? 50,
      ]);

      return rows.map(hookOf);
    },
  };
}
