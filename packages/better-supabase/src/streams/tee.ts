import type { DbError } from "../core/errors.ts";
import type { StreamOpenOptions, StreamStore } from "./store.ts";

import {
  AsyncResult,
  err,
  ok,
  type Result,
  toDbError,
} from "../core/result.ts";

export interface TeeToStoreOptions extends StreamOpenOptions {
  /** Milliseconds a chunk may wait before its batch is written. Defaults to 100. */
  readonly flushMs?: number;
  /** Bytes that trigger a write before `flushMs`. Defaults to 4096. */
  readonly flushBytes?: number;
  /**
   * Called once when the store reports the stream cancelled. Abort the
   * generation here, e.g. the `AbortController` passed to `streamText`.
   */
  readonly onCancel?: () => void;
}

export interface TeedStream {
  /** The source, for the live response. */
  readonly stream: ReadableStream<string>;
  /**
   * Settles once every chunk is stored and the stream is closed, with the
   * number of chunks. It keeps going after the live client disconnects, so
   * hand it to `waitUntil` or `after`.
   */
  readonly persisted: AsyncResult<number>;
}

/**
 * Copies `source` into `store` under `id` while passing it through. Chunks
 * are written in batches, each at its own index, so a reader that counted
 * `n` chunks of the live stream resumes with `read(id, n)`.
 */
export function teeToStore(
  store: StreamStore,
  id: string,
  source: ReadableStream<string>,
  options: TeeToStoreOptions = {},
): TeedStream {
  const [live, copy] = source.tee();
  return {
    stream: live,
    persisted: AsyncResult.from(() => persist(store, id, copy, options)),
  };
}

/**
 * Stores `source` under `id` without a live copy, for a stream the caller
 * already sends elsewhere (the second branch of its own `tee()`). Settles
 * like `teeToStore`'s `persisted`.
 */
export function writeToStore(
  store: StreamStore,
  id: string,
  source: ReadableStream<string>,
  options: TeeToStoreOptions = {},
): AsyncResult<number> {
  return AsyncResult.from(() => persist(store, id, source, options));
}

async function persist(
  store: StreamStore,
  id: string,
  copy: ReadableStream<string>,
  options: TeeToStoreOptions,
): Promise<Result<number>> {
  const { flushMs = 100, flushBytes = 4096, onCancel } = options;
  const opened = await store.open(id, {
    ...(options.owner === undefined ? {} : { owner: options.owner }),
    ...(options.tenant === undefined ? {} : { tenant: options.tenant }),
    ...(options.kind === undefined ? {} : { kind: options.kind }),
    ...(options.ttl === undefined ? {} : { ttl: options.ttl }),
  });
  if (!opened.ok) {
    // A tee branch's cancel settles only once the live branch is cancelled too.
    void copy.cancel().catch(() => undefined);
    return opened;
  }
  let next = 0;
  let buffer: string[] = [];
  let bytes = 0;
  let failure: DbError | undefined;
  let cancelled = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let writing: Promise<void> = Promise.resolve();

  const flush = (): Promise<void> => {
    if (timer !== undefined) clearTimeout(timer);
    timer = undefined;
    if (buffer.length === 0) return writing;
    const batch = buffer;
    const from = next;
    buffer = [];
    bytes = 0;
    next += batch.length;
    writing = writing.then(async () => {
      if (failure) return;
      const appended = await store.append(id, from, batch);
      if (!appended.ok) {
        failure = appended.error;
        return;
      }
      if (appended.data.cancelled && !cancelled) {
        cancelled = true;
        onCancel?.();
      }
    });
    return writing;
  };

  const reader = copy.getReader();
  let sourceError: unknown;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer.push(value);
      bytes += value.length;
      if (bytes >= flushBytes) void flush();
      else timer ??= setTimeout(() => void flush(), flushMs);
      if (failure) break;
    }
  } catch (cause) {
    sourceError = cause;
  } finally {
    reader.releaseLock();
  }
  await flush();
  if (failure) {
    void copy.cancel().catch(() => undefined);
    return err(failure);
  }
  const closed = await store.close(id);
  if (!closed.ok) return closed;
  return sourceError === undefined ? ok(next) : err(toDbError(sourceError));
}

export interface ResumeFromStoreOptions {
  /** The number of chunks the client already has. Defaults to 0. */
  readonly fromIdx?: number;
  readonly signal?: AbortSignal;
}

/**
 * The rest of stream `id` from `fromIdx`, or `undefined` when there is
 * nothing to resume: no such stream, or a closed one the client has read to
 * the end. A route answers `undefined` with 204.
 */
export function resumeFromStore(
  store: StreamStore,
  id: string,
  options: ResumeFromStoreOptions = {},
): AsyncResult<ReadableStream<string> | undefined> {
  const from = options.fromIdx ?? 0;
  return store
    .status(id)
    .map((status) =>
      status === undefined || (status.closed && from >= status.next)
        ? undefined
        : store.read(
            id,
            from,
            options.signal === undefined ? {} : { signal: options.signal },
          ),
    );
}
