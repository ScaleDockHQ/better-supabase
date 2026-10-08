import type { AsyncResult, Result } from "../core/result.ts";

/** How a stream is opened. */
export interface StreamOpenOptions {
  /** The user who may read the stream and cancel it. */
  readonly owner?: string;
  readonly tenant?: string;
  /** What the stream carries, such as `chat` or `workflow`. Defaults to `default`. */
  readonly kind?: string;
  /** Seconds the stream lives, or a Postgres interval such as `"2 hours"`. Defaults to one day. */
  readonly ttl?: number | string;
}

export interface StreamAppendResult {
  /** The index the next chunk gets. */
  readonly next: number;
  /** Someone asked the writer to stop. */
  readonly cancelled: boolean;
}

export interface StreamStatus {
  /** The number of chunks stored. */
  readonly next: number;
  readonly closed: boolean;
  readonly cancelled: boolean;
}

export interface StreamReadOptions {
  /** Ends the stream early. */
  readonly signal?: AbortSignal;
}

export interface StreamPurgeOptions {
  /** How long a closed stream is kept: seconds or an interval. Defaults to one day. */
  readonly olderThan?: number | string;
}

/**
 * Durable, resumable output: one writer appends ordered text chunks and any
 * number of readers read from a chunk index, live or after a reconnect.
 * Chunks keep the index they were appended at, so a reader that counted `n`
 * chunks resumes with `read(id, n)`.
 */
export interface StreamStore {
  readonly apiVersion: 1;
  readonly name: string;
  /** Creates the stream; `true` when it was new, `false` when it existed. */
  open(id: string, options?: StreamOpenOptions): AsyncResult<boolean>;
  /**
   * Stores `chunks` at `fromIdx`, `fromIdx + 1`, ... Indexes already stored
   * are skipped, so a retried batch is harmless. Fails with the hint
   * `STREAM_NOT_FOUND`, `STREAM_CLOSED` or `STREAM_GAP` (`fromIdx` past the
   * end).
   */
  append(
    id: string,
    fromIdx: number,
    chunks: readonly string[],
  ): AsyncResult<StreamAppendResult>;
  /**
   * The chunks from `fromIdx` on, waiting for new ones until the stream is
   * closed. A stream that doesn't exist (or that the caller can't read) ends
   * at once. A read error errors the stream with the `DbError`.
   */
  read(
    id: string,
    fromIdx?: number,
    options?: StreamReadOptions,
  ): ReadableStream<string>;
  /** The stream's state, or `undefined` when it doesn't exist. */
  status(id: string): AsyncResult<StreamStatus | undefined>;
  isCancelled(id: string): AsyncResult<boolean>;
  /** Marks the stream finished; `false` when it was closed already or doesn't exist. */
  close(id: string): AsyncResult<boolean>;
  /** Asks the writer to stop; it learns on its next append. */
  cancel(id: string): AsyncResult<boolean>;
  /** Deletes expired streams and closed ones past `olderThan`; resolves with the count. */
  purge(options?: StreamPurgeOptions): AsyncResult<number>;
}

/** One page of a read. */
export interface StreamPage {
  readonly chunks: readonly string[];
  readonly next: number;
  readonly done: boolean;
}

export interface PollingReadOptions {
  readonly fetch: (from: number) => PromiseLike<Result<StreamPage>>;
  readonly from: number;
  readonly pollMs: number;
  readonly signal: AbortSignal | undefined;
  /** Calls `wake` when new chunks may be there; returns the unsubscribe. */
  readonly subscribe?: (wake: () => void) => () => void;
}

/** A reader that fetches pages and waits for a wake-up or `pollMs` between empty ones. */
export function pollingRead(
  options: PollingReadOptions,
): ReadableStream<string> {
  let next = options.from;
  let woken = false;
  let resolveWait: (() => void) | undefined;
  const wake = (): void => {
    woken = true;
    resolveWait?.();
  };
  let unsubscribe: (() => void) | undefined;
  const stop = (): void => {
    unsubscribe?.();
    unsubscribe = undefined;
    options.signal?.removeEventListener("abort", wake);
  };
  const wait = (): Promise<void> =>
    new Promise<void>((resolve) => {
      if (woken || options.signal?.aborted) {
        resolve();
        return;
      }
      const timer = setTimeout(done, options.pollMs);
      function done(): void {
        clearTimeout(timer);
        resolveWait = undefined;
        resolve();
      }
      resolveWait = done;
    });
  return new ReadableStream<string>({
    start() {
      options.signal?.addEventListener("abort", wake, { once: true });
      unsubscribe = options.subscribe?.(wake);
    },
    async pull(controller) {
      for (;;) {
        if (options.signal?.aborted) {
          stop();
          controller.close();
          return;
        }
        woken = false;
        const page = await options.fetch(next);
        if (!page.ok) {
          stop();
          controller.error(page.error);
          return;
        }
        for (const chunk of page.data.chunks) controller.enqueue(chunk);
        next = page.data.next;
        if (page.data.done) {
          stop();
          controller.close();
          return;
        }
        if (page.data.chunks.length > 0) return;
        await wait();
      }
    },
    cancel() {
      stop();
    },
  });
}
