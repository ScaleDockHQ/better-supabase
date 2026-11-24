import { headers } from "next/headers.js";

import type { CacheEntryStat, StatsRecorder } from "../core/stats.ts";
import type { ContextOptions } from "../server/server-types.ts";
import type { CollectorView } from "./collector.ts";
import type { CacheScope, RemoteCacheKey } from "./types.ts";

import { recordingFetch } from "../core/stats.ts";
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
  /** The current request's debug id, `undefined` without debug. */
  readonly currentId: () => Promise<string | undefined>;
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
