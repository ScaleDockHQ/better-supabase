import { headers } from "next/headers.js";

import type { CacheEntryStat, StatsRecorder } from "../core/stats.ts";
import type { ContextOptions } from "../server/server-types.ts";
import type { CollectorView } from "./collector.ts";
import type { RemoteCacheKey } from "./types.ts";

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
}

const roundMs = (ms: number): number => Math.round(ms * 100) / 100;

export function requestRecording(
  collector: CollectorView | undefined,
): RequestRecording {
  const currentId = async (): Promise<string | undefined> =>
    collector ? headers().then(requestIdOf, () => undefined) : undefined;

  const statsForId = (id: string | undefined): ContextOptions =>
    collector && id ? { stats: collector.recorderFor(id) } : {};

  return {
    statsForId,
    statsForHandle: (handle) => statsForId(handoffRequestId(handle)),

    recordOn: (handle, record) => {
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
    },

    currentId,

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
