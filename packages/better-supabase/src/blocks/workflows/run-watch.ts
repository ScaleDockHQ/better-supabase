import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort } from "../controller.ts";

import { whileSignedIn } from "../controller.ts";

export interface RunWatchOptions<S extends object> {
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The run's id or its engine's id; `null` waits. */
  readonly run: string | null;
  /** Loads the run and whatever else the snapshot holds; resolves with the run's id. */
  readonly load: () => Promise<{
    readonly id: string | null;
    readonly patch: Partial<S>;
  }>;
}

/**
 * The shared part of the run controllers: loads while signed in, then
 * joins `workflow-run:<id>` once the run's id is known.
 */
export function watchRun<S extends { readonly status: SubscriptionStatus }>(
  options: RunWatchOptions<S>,
  state: {
    readonly set: (patch: Partial<S>) => void;
    readonly run: () => number;
  },
): {
  readonly refresh: () => Promise<void>;
  readonly start: () => (() => void) | undefined;
} {
  let joined: { readonly id: string; readonly leave: () => void } | undefined;
  let live = false;
  const join = (id: string | null): void => {
    if (!live || id === null || joined?.id === id) return;
    joined?.leave();
    joined = {
      id,
      leave: options.ports.topic(`workflow-run:${id}`, {
        onMessage: () => void refresh(),
        onRejoin: () => void refresh(),
        onStatus: (status) => {
          // SAFETY: S extends { status: SubscriptionStatus }.
          state.set({ status } as Partial<S>);
        },
      }).leave,
    };
  };
  const refresh = async (): Promise<void> => {
    if (options.run === null) return;
    const run = state.run();
    const loaded = await options.load();
    if (run !== state.run()) return;
    state.set(loaded.patch);
    join(loaded.id);
  };
  return {
    refresh,
    start: () => {
      if (options.run === null) return;
      return whileSignedIn(options.auth, () => {
        live = true;
        void refresh();
        return () => {
          live = false;
          joined?.leave();
          joined = undefined;
        };
      });
    },
  };
}

/** The error of the first failed result, or `undefined` when all passed. */
export function firstError(
  ...results: readonly Result<unknown>[]
): DbError | undefined {
  for (const result of results) if (!result.ok) return result.error;
  return;
}
