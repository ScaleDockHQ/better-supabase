import type { Result } from "../core/result.ts";
import type { StreamStore } from "../streams/store.ts";

import { type ConformanceReport, conform, expect } from "./conformance.ts";

export interface TestStreamStoreOptions {
  /** A fresh stream id per call. Defaults to `conformance-<uuid>`. */
  readonly id?: () => string;
  /** Milliseconds a read may take before the check fails. Defaults to 5000. */
  readonly timeoutMs?: number;
}

async function collect(
  stream: ReadableStream<string>,
  timeoutMs: number,
): Promise<string[]> {
  const chunks: string[] = [];
  const reader = stream.getReader();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error(`read did not end within ${String(timeoutMs)} ms`));
    }, timeoutMs);
  });
  try {
    for (;;) {
      const { done, value } = await Promise.race([reader.read(), timeout]);
      if (done) return chunks;
      chunks.push(value);
    }
  } finally {
    clearTimeout(timer);
    await reader.cancel().catch(() => undefined);
  }
}

const hintOf = (result: Result<unknown>): string | undefined =>
  result.ok ? undefined : result.error.hint;

/**
 * Runs the `StreamStore` contract against `store`: the API version, open
 * once, idempotent appends that refuse gaps, reads from any index that end
 * when the stream closes, a live read that sees later appends, cancel seen by
 * the writer, a closed stream that refuses appends, and a missing stream.
 */
export function testStreamStore(
  store: StreamStore,
  options: TestStreamStoreOptions = {},
): Promise<ConformanceReport> {
  const fresh = options.id ?? (() => `conformance-${crypto.randomUUID()}`);
  const timeoutMs = options.timeoutMs ?? 5000;
  return conform(`StreamStore "${store.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = store.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(store.name.length > 0, "name is empty");
      },
    ],
    [
      "opens a stream once",
      async () => {
        const id = fresh();
        expect(await store.open(id).orThrow(), "first open was not new");
        expect(!(await store.open(id).orThrow()), "second open was new");
      },
    ],
    [
      "appends idempotently and refuses a gap",
      async () => {
        const id = fresh();
        await store.open(id).orThrow();
        const first = await store.append(id, 0, ["a", "b"]).orThrow();
        expect(
          first.next === 2,
          `next after two chunks is ${String(first.next)}`,
        );
        const retried = await store.append(id, 0, ["a", "b", "c"]).orThrow();
        expect(
          retried.next === 3,
          `next after a retried batch is ${String(retried.next)}`,
        );
        const gap = await store.append(id, 5, ["x"]);
        expect(
          hintOf(gap) === "STREAM_GAP",
          `a gap gave ${JSON.stringify(gap)}`,
        );
        await store.close(id).orThrow();
        const chunks = await collect(store.read(id), timeoutMs);
        expect(
          chunks.join("") === "abc",
          `read ${JSON.stringify(chunks)} after a retried batch`,
        );
      },
    ],
    [
      "reads from an index and ends once closed",
      async () => {
        const id = fresh();
        await store.open(id).orThrow();
        await store.append(id, 0, ["0", "1", "2", "3"]).orThrow();
        expect(await store.close(id).orThrow(), "close returned false");
        expect(
          !(await store.close(id).orThrow()),
          "a second close returned true",
        );
        const tail = await collect(store.read(id, 2), timeoutMs);
        expect(
          tail.join(",") === "2,3",
          `read from 2 gave ${JSON.stringify(tail)}`,
        );
        const status = await store.status(id).orThrow();
        expect(
          status?.next === 4 && status.closed && !status.cancelled,
          `status is ${JSON.stringify(status)}`,
        );
      },
    ],
    [
      "a live read sees later appends",
      async () => {
        const id = fresh();
        await store.open(id).orThrow();
        const reading = collect(store.read(id), timeoutMs);
        await store.append(id, 0, ["x"]).orThrow();
        await store.append(id, 1, ["y"]).orThrow();
        await store.close(id).orThrow();
        const chunks = await reading;
        expect(
          chunks.join("") === "xy",
          `live read gave ${JSON.stringify(chunks)}`,
        );
      },
    ],
    [
      "tells the writer about a cancel",
      async () => {
        const id = fresh();
        await store.open(id).orThrow();
        expect(
          !(await store.isCancelled(id).orThrow()),
          "a new stream is cancelled",
        );
        expect(await store.cancel(id).orThrow(), "cancel returned false");
        expect(
          await store.isCancelled(id).orThrow(),
          "isCancelled is false after cancel",
        );
        const appended = await store.append(id, 0, ["late"]).orThrow();
        expect(appended.cancelled, "append did not report the cancel");
        await store.close(id).orThrow();
        expect(
          !(await store.cancel(id).orThrow()),
          "cancel of a closed stream returned true",
        );
      },
    ],
    [
      "refuses appends to a closed stream",
      async () => {
        const id = fresh();
        await store.open(id).orThrow();
        await store.close(id).orThrow();
        const closed = await store.append(id, 0, ["x"]);
        expect(
          hintOf(closed) === "STREAM_CLOSED",
          `append gave ${JSON.stringify(closed)}`,
        );
      },
    ],
    [
      "treats a missing stream as empty",
      async () => {
        const id = fresh();
        expect(
          (await store.status(id).orThrow()) === undefined,
          "status of a missing stream",
        );
        const chunks = await collect(store.read(id), timeoutMs);
        expect(
          chunks.length === 0,
          `read a missing stream as ${JSON.stringify(chunks)}`,
        );
        const appended = await store.append(id, 0, ["x"]);
        expect(
          hintOf(appended) === "STREAM_NOT_FOUND",
          `append gave ${JSON.stringify(appended)}`,
        );
      },
    ],
    [
      "purges with a count",
      async () => {
        const purged = await store.purge().orThrow();
        expect(
          Number.isInteger(purged) && purged >= 0,
          `purge returned ${String(purged)}`,
        );
      },
    ],
  ]);
}
