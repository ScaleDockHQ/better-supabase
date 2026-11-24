import { after } from "next/server.js";

import type { BetterSupabase } from "../core/define.ts";
import type { DbStats } from "../core/stats.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { CollectorView } from "./collector.ts";
import type { NextOptions } from "./types.ts";

import { coldPending, recordCold } from "../core/cold-start.ts";
import { flushEvents } from "../server/adapter.ts";
import { logColdStart, takeColdStart } from "./cold-start.ts";
import {
  DEFAULT_ROUND_TRIPS,
  devBudget,
  formatStats,
  sharedCollector,
} from "./collector.ts";

/** The request bookkeeping `createNext` and `createProxy` share. */
export interface ProxyRuntime {
  readonly collector: CollectorView | undefined;
  readonly statsHeader: string;
  /** The stats header's value, with `debug.coldStart`'s `cold=` field. */
  readonly statsValue: (stats: DbStats) => string;
  readonly statsRoute: string;
  readonly development: boolean;
  readonly waitUntil: (work: Promise<unknown>) => void;
  /** Keeps the function alive for event sink sends the handler started. */
  readonly flushAfter: () => void;
}

export function proxyRuntime<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: Pick<NextOptions, "debug" | "devRoundTripBudget">,
): ProxyRuntime {
  const debug = options.debug;
  const statsHeader = debug?.header ?? "x-bsb-db-calls";
  const statsRoute = debug?.route ?? "/api/bsb-stats";
  const development = process.env["NODE_ENV"] === "development";

  const roundTrips = options.devRoundTripBudget ?? DEFAULT_ROUND_TRIPS;
  const watching = development && roundTrips !== false;

  const budget = debug?.budget ?? devBudget(watching && roundTrips);

  const collector =
    debug?.enabled || debug?.coldStart || watching
      ? sharedCollector({
          logger: betterSupabase.events.logger,
          warn: development,
          ...(budget ? { budget } : {}),
        })
      : undefined;

  const coldStart = debug?.coldStart === true;

  if (coldStart) {
    const { events } = betterSupabase;

    logColdStart((line) => {
      events.logger.info(line);
    });

    if (coldPending("query")) {
      const off = events.on("query", (event) => {
        off();
        recordCold("query", event.durationMs);
      });
    }
  }

  const statsValue = (stats: DbStats): string => {
    const value = formatStats(stats);
    const cold = coldStart ? takeColdStart() : undefined;

    return cold === undefined ? value : `${value};cold=${cold}`;
  };

  const waitUntil = (work: Promise<unknown>): void => {
    try {
      after(() => work);
    } catch (cause) {
      // after() only works inside a request scope; the sends still run.
      betterSupabase.events.logger.warn(
        "after() is unavailable; event sends may be cut off",
        { cause },
      );
    }
  };

  /** Keeps the function alive for event sink sends the handler started. */
  const flushAfter = (): void => {
    flushEvents(betterSupabase, waitUntil);
  };

  return {
    collector,
    statsHeader,
    statsValue,
    statsRoute,
    development,
    waitUntil,
    flushAfter,
  };
}
