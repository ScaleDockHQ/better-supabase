import { headers } from "next/headers.js";

import type {
  CacheEntryStat,
  StatsPhase,
  StatsRecorder,
} from "../core/stats.ts";
import type { Settled } from "../server/respond.ts";
import type { ContextOptions } from "../server/server-types.ts";
import type { CollectorView } from "./collector.ts";
import type { CacheScope, RemoteCacheKey } from "./types.ts";

import { recordingFetch, setAmbientStats } from "../core/stats.ts";
import { settle } from "../server/respond.ts";
import { requestIdOf } from "./collector.ts";
import { fillsOf, handoffRequestId } from "./remote-handoff.ts";

/** Where a server's calls, tag calls and cache entries are counted. */
export interface RequestRecording {
  /** The context option that counts a scope's calls for request `id`. */
  readonly statsForId: (id: string | undefined) => ContextOptions;
  /** The same for the request that made a session handle or a remote key. */
  readonly statsForHandle: (handle: RemoteCacheKey) => ContextOptions;
  /**
   * Runs `record` on the recorder of the request `handle` came from, or of the
   * current request.
   */
  readonly recordOn: (
    handle: RemoteCacheKey | undefined,
    record: (recorder: StatsRecorder) => void,
  ) => void;
  /**
   * Runs `run` with the request's calls marked as `phase`, then puts the phase
   * back. Without debug it only runs `run`.
   */
  readonly inPhase: <T>(phase: StatsPhase, run: () => Promise<T>) => Promise<T>;
  /** The current request's debug id, `undefined` without debug. */
  readonly currentId: () => Promise<string | undefined>;
  /** Settles `run` with the request's calls marked as `phase`, then `render`. */
  readonly settleIn: (
    phase: StatsPhase,
    run: () => unknown,
  ) => Promise<Settled>;
  /**
   * Starts timing a `bsb.remote()` call under `key`; the returned function
   * records it as a hit or, when a fill ran meanwhile, a miss.
   */
  readonly remoteCall: (
    key: RemoteCacheKey,
    id: string,
    requestId: string | undefined,
  ) => () => void;
  readonly statsFetch: (base?: typeof globalThis.fetch) => typeof fetch;
  /**
   * Records that a private or public entry's body ran, which is a miss. A
   * remote entry (`bsb.remote()`) records itself through `remoteCall`.
   */
  readonly missed: (scope: CacheScope, entry: EntryOptions) => void;
}

/** The part of an entry's options that names it. */
interface EntryOptions {
  readonly scope?: "private" | "remote";
  readonly tables?: readonly string[];
  readonly tags?: readonly string[];
}

const roundMs = (ms: number): number => Math.round(ms * 100) / 100;

export function requestRecording(
  collector: CollectorView | undefined,
): RequestRecording {
  const currentId = async (): Promise<string | undefined> =>
    collector ? headers().then(requestIdOf, () => undefined) : undefined;

  // A service that calls `connect()` itself has no recorder to pass; it finds
  // the current request's through this.
  setAmbientStats(
    collector
      ? async () => {
          const id = await currentId();

          return id ? collector.recorderFor(id) : undefined;
        }
      : undefined,
  );

  const statsForId = (id: string | undefined): ContextOptions =>
    collector && id ? { stats: collector.recorderFor(id) } : {};

  const recordOn: RequestRecording["recordOn"] = (handle, record) => {
    if (!collector) {
      return;
    }

    const fromHandle = handle ? handoffRequestId(handle) : undefined;

    (fromHandle ? Promise.resolve(fromHandle) : currentId())
      .then((found) => {
        if (found) {
          record(collector.recorderFor(found));
        }
      })
      .catch(() => {
        // Outside a request there is no request to record on.
      });
  };

  return {
    statsForId,
    statsForHandle: (handle) => statsForId(handoffRequestId(handle)),
    recordOn,
    currentId,
    inPhase: async (phase, run) => {
      if (!collector) {
        return run();
      }

      const id = await currentId();
      const recorder = id ? collector.recorderFor(id) : undefined;

      if (!recorder) {
        return run();
      }

      const before = recorder.phase;

      recorder.setPhase(phase);

      try {
        return await run();
      } finally {
        recorder.setPhase(before);
      }
    },

    settleIn: async (phase, run) => {
      const id = await currentId();
      const recorder = collector && id ? collector.recorderFor(id) : undefined;

      recorder?.setPhase(phase);

      try {
        return await settle(run);
      } finally {
        recorder?.setPhase("render");
      }
    },

    missed: (scope, entry) => {
      const kind =
        scope === "remote" ? (entry.scope ? undefined : "public") : "private";

      if (kind) {
        recordOn(undefined, (recorder) => {
          recorder.entry({
            id: entry.tables?.[0] ?? entry.tags?.[0] ?? kind,
            kind,
            outcome: "miss",
          });
        });
      }
    },

    remoteCall: (key, id, requestId) => {
      if (!collector || !requestId) {
        return () => undefined;
      }

      const name = id || "remote";
      const fills = fillsOf(key);
      const started = performance.now();

      return () => {
        const filled = fillsOf(key) > fills;

        const record: CacheEntryStat = filled
          ? {
              id: name,
              kind: "remote",
              outcome: "miss",
              fillMs: roundMs(performance.now() - started),
            }
          : { id: name, kind: "remote", outcome: "hit" };

        collector.recorderFor(requestId).entry(record);
      };
    },

    statsFetch: (base = globalThis.fetch) => {
      if (!collector) {
        return base;
      }

      return async (input, init) => {
        const id = await currentId();

        return id
          ? recordingFetch(collector.recorderFor(id), () => base)(input, init)
          : base(input, init);
      };
    },
  };
}
