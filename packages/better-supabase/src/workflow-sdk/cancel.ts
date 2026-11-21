import type { World } from "@workflow/world";

import { getRun } from "workflow/api";
import { getWorld } from "workflow/runtime";

import type { AsyncResult } from "../core/result.ts";

import { run } from "../blocks/shared.ts";
import { WORKFLOW_ATTRIBUTES } from "./attributes.ts";

/** A run status that can still be cancelled. */
const OPEN_STATUSES = ["pending", "running"] as const;

export interface CancelTenantRunsOptions {
  /** The World to cancel in. Defaults to the configured one. */
  readonly world?: World;
  /** Only runs of this workflow. */
  readonly workflowName?: string;
  /** Recorded as the cancel reason on every run, where the World keeps one. */
  readonly reason?: string;
  /** Runs per `cancelMany` call or per concurrent batch. Defaults to 100. */
  readonly batch?: number;
  /** Stops after this many runs. Defaults to 10000. */
  readonly limit?: number;
}

export interface CancelTenantRunsResult {
  readonly requested: number;
  readonly cancelled: number;
  /** Runs that were already cancelled or had finished. */
  readonly settled: number;
  /** Runs whose cancel failed, for the caller to retry. */
  readonly failed: readonly string[];
}

const CONCURRENCY = 8;

async function cancelBatch(
  world: World,
  ids: readonly string[],
  reason: string | undefined,
): Promise<{
  readonly cancelled: number;
  readonly settled: number;
  readonly failed: string[];
}> {
  const cancelMany = world.runs.cancelMany?.bind(world.runs);

  if (cancelMany !== undefined) {
    const report = await cancelMany({
      runIds: [...ids],
      ...(reason === undefined ? {} : { cancelReason: reason }),
    });

    const failed: string[] = [];
    let cancelled = 0;
    let settled = 0;

    for (const result of report.results) {
      switch (result.outcome) {
        case "cancelled": {
          cancelled += 1;
          break;
        }

        case "failed": {
          failed.push(result.runId);
          break;
        }

        case "already_cancelled":
        case "not_cancellable":
        case "not_found": {
          settled += 1;
          break;
        }

        default: {
          const unknown: never = result;

          return unknown;
        }
      }
    }

    return { cancelled, settled, failed };
  }

  const failed: string[] = [];
  let cancelled = 0;

  for (let at = 0; at < ids.length; at += CONCURRENCY) {
    const slice = ids.slice(at, at + CONCURRENCY);

    const done = await Promise.allSettled(
      slice.map((id) =>
        getRun(id).cancel(reason === undefined ? {} : { cancelReason: reason }),
      ),
    );

    for (const [index, outcome] of done.entries()) {
      if (outcome.status === "fulfilled") {
        cancelled += 1;
      } else {
        failed.push(slice[index] ?? "");
      }
    }
  }

  return { cancelled, settled: 0, failed };
}

/**
 * Cancels every open run that carries the `bsb.tenant` attribute `tenant`, for
 * an offboarded or suspended tenant. It lists runs through the World's
 * `analytics`, then cancels them in batches: with `runs.cancelMany` where the
 * World has it (Vercel), one run at a time otherwise. A run that ended since
 * the listing counts as settled. It never throws for a World error: failed run
 * ids come back in `failed` and the call can be repeated, since cancelling is
 * idempotent. Needs a World with `analytics`.
 */
export function cancelTenantRuns(
  tenant: string,
  options: CancelTenantRunsOptions = {},
): AsyncResult<CancelTenantRunsResult> {
  return run(async () => {
    if (tenant === "") {
      throw new TypeError("better-supabase: cancelTenantRuns needs a tenant");
    }

    const world = options.world ?? (await getWorld());

    if (world.analytics === undefined) {
      throw new TypeError(
        "better-supabase: cancelTenantRuns needs a World with analytics to list the tenant's runs",
      );
    }

    const batch = Math.max(1, Math.min(options.batch ?? 100, 100));
    const limit = options.limit ?? 10_000;
    const ids = new Set<string>();

    for (const status of OPEN_STATUSES) {
      let cursor: string | undefined;

      while (ids.size < limit) {
        const page = await world.analytics.runs.list({
          status,
          attributes: { [WORKFLOW_ATTRIBUTES.tenant]: tenant },
          pagination: {
            limit: 1000,
            ...(cursor === undefined ? {} : { cursor }),
          },
          ...(options.workflowName === undefined
            ? {}
            : { workflowName: options.workflowName }),
        });

        for (const item of page.data) {
          ids.add(item.runId);
        }

        if (!page.hasMore || page.cursor === null) {
          break;
        }

        cursor = page.cursor;
      }
    }

    const all = [...ids].slice(0, limit);
    let cancelled = 0;
    let settled = 0;
    const failed: string[] = [];

    for (let at = 0; at < all.length; at += batch) {
      const result = await cancelBatch(
        world,
        all.slice(at, at + batch),
        options.reason,
      );

      cancelled += result.cancelled;
      settled += result.settled;
      failed.push(...result.failed);
    }

    return { requested: all.length, cancelled, settled, failed };
  });
}
