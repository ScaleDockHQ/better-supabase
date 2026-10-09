import type { SupabaseClient } from "@supabase/supabase-js";

import type { BlockTransport } from "../core/block-transport.ts";
import type { ErrorMapper } from "../core/errors.ts";
import type { StreamPage, StreamStatus, StreamStore } from "./store.ts";

import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  isRecord,
  recordOf,
  seconds,
  stringsOf,
} from "../core/block-helpers.ts";
import { pollingRead } from "./store.ts";

export interface PostgresStreamStoreOptions {
  /** `sqlTransport(postgres.asService())` for the writer; the owner's transport for reads. */
  readonly transport: BlockTransport;
  /** The schema of the `streams` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `realtime` (the default) pings the stream's private topic after each
   * batch; `poll` skips the ping for apps near the Realtime message quota,
   * and readers poll instead.
   */
  readonly wake?: "realtime" | "poll";
  /** A Supabase client a reader joins the topic with, to wake up on the ping. */
  readonly realtime?: Pick<SupabaseClient, "channel" | "removeChannel">;
  /** `sql.modules.streams.options.topic`. Defaults to `stream`. */
  readonly topic?: string;
  /** Milliseconds between reads of an idle stream: 250 by default, 2000 with `realtime`. */
  readonly pollMs?: number;
  /** Chunks per read. Defaults to 1000. */
  readonly batch?: number;
}

function statusOf(value: unknown): StreamStatus | undefined {
  if (!isRecord(value)) return undefined;
  return {
    next: Number(value["next"] ?? 0),
    closed: value["closed"] === true,
    cancelled: value["cancelled"] === true,
  };
}

/** A `StreamStore` on the `streams` SQL module. */
export function postgresStreamStore(
  options: PostgresStreamStoreOptions,
): StreamStore {
  const call = blockCall(
    options.transport,
    options.schema ?? DEFAULT_BLOCK_SCHEMA,
    options.mappers,
  );
  const wake = (options.wake ?? "realtime") === "realtime";
  const topic = options.topic ?? "stream";
  const realtime = wake ? options.realtime : undefined;
  const pollMs = options.pollMs ?? (realtime ? 2000 : 250);
  const batch = options.batch ?? 1000;

  const subscribe = realtime
    ? (id: string) =>
        (onWake: () => void): (() => void) => {
          const channel = realtime
            .channel(`${topic}:${id}`, { config: { private: true } })
            .on("broadcast", { event: "*" }, onWake)
            .subscribe();
          return () => {
            void realtime.removeChannel(channel);
          };
        }
    : undefined;

  const status: StreamStore["status"] = (id) =>
    call("stream_status", { stream_id: id }, statusOf);

  return {
    apiVersion: 1,
    name: "postgres",
    open: (id, open = {}) =>
      call(
        "stream_open",
        {
          stream_id: id,
          owner: open.owner,
          tenant: open.tenant,
          kind: open.kind,
          ttl: open.ttl === undefined ? undefined : seconds(open.ttl),
          wake,
        },
        (value) => value === true,
      ),
    append: (id, fromIdx, chunks) =>
      call(
        "stream_append",
        { stream_id: id, from_idx: fromIdx, chunks: [...chunks] },
        (value) => {
          const row = recordOf(value, "stream_append");
          return {
            next: Number(row["next"]),
            cancelled: row["cancelled"] === true,
          };
        },
      ),
    read: (id, fromIdx = 0, read = {}) =>
      pollingRead({
        from: fromIdx,
        pollMs,
        signal: read.signal,
        ...(subscribe ? { subscribe: subscribe(id) } : {}),
        fetch: (from) =>
          call(
            "stream_read",
            { stream_id: id, from_idx: from, max: batch },
            (value): StreamPage => {
              const row = recordOf(value, "stream_read");
              return {
                chunks: stringsOf(row["chunks"]),
                next: Number(row["next"]),
                done: row["done"] === true,
              };
            },
          ),
      }),
    status,
    isCancelled: (id) => status(id).map((state) => state?.cancelled === true),
    close: (id) =>
      call("stream_close", { stream_id: id }, (value) => value === true),
    cancel: (id) =>
      call("stream_cancel", { stream_id: id }, (value) => value === true),
    purge: (purge = {}) =>
      call(
        "purge_streams",
        {
          older_than:
            purge.olderThan === undefined
              ? undefined
              : seconds(purge.olderThan),
        },
        Number,
      ),
  };
}
