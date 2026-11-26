import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { blockCall } from "../../src/core/block-helpers.ts";
import {
  READ_BATCH_LIMIT,
  readBatch,
  readBatchMemory,
} from "../../src/core/read-batch.ts";

type Args = Readonly<Record<string, unknown>>;

interface Batched {
  readonly fn: string;
  readonly args: Args;
}

/** An inner transport that answers `read_batch` with `entry` per call. */
function fakeInner(
  entry: (call: Batched) => unknown = (call) => ({ data: call.fn }),
  batch?: () => Promise<unknown>,
) {
  const call = vi.fn<
    (schema: string, fn: string, args: Args) => Promise<unknown>
  >((_schema, fn, args) => {
    if (fn !== "read_batch") {
      return Promise.resolve(`direct:${fn}`);
    }

    if (batch) {
      return batch();
    }

    // SAFETY: the batch transport sends `{ calls }`.
    const calls = (args as { readonly calls: readonly Batched[] }).calls;

    return Promise.resolve(calls.map(entry));
  });

  return { call };
}

/** Runs each `fn` as a participant, all started in the same tick. */
const together = <T>(
  run: <R>(fn: () => Promise<R>) => Promise<R>,
  fns: readonly (() => Promise<T>)[],
): Promise<T[]> => Promise.all(fns.map((fn) => run(fn)));

describe("readBatch", () => {
  it("sends the first reads of every participant as one read_batch call", async () => {
    const inner = fakeInner();
    const batch = readBatch(inner);

    const results = await together(batch.run, [
      () => batch.transport.call("api", "tags_of", { id: "1" }),
      () => batch.transport.call("api", "fields_of", { id: "1" }),
      () => batch.transport.call("api", "files_of", { id: "1" }),
    ]);

    expect(results).toEqual(["tags_of", "fields_of", "files_of"]);
    expect(inner.call).toHaveBeenCalledExactlyOnceWith("api", "read_batch", {
      calls: [
        { fn: "tags_of", args: { id: "1" } },
        { fn: "fields_of", args: { id: "1" } },
        { fn: "files_of", args: { id: "1" } },
      ],
    });
  });

  it("sends one call per schema, and a schema with one call goes direct", async () => {
    const inner = fakeInner();
    const batch = readBatch(inner);

    const results = await together(batch.run, [
      () => batch.transport.call("api", "a", {}),
      () => batch.transport.call("api", "b", {}),
      () => batch.transport.call("other", "c", {}),
    ]);

    expect(results).toEqual(["a", "b", "direct:c"]);
    expect(inner.call).toHaveBeenCalledTimes(2);
    expect(inner.call).toHaveBeenCalledWith("other", "c", {});
  });

  it("calls a single participant's read directly", async () => {
    const inner = fakeInner();
    const batch = readBatch(inner);

    await expect(
      batch.run(() => batch.transport.call("api", "tags_of", {})),
    ).resolves.toBe("direct:tags_of");
    expect(inner.call).toHaveBeenCalledWith("api", "tags_of", {});
  });

  it("calls a read outside any participant directly", async () => {
    const inner = fakeInner();
    const batch = readBatch(inner);

    await expect(batch.transport.call("api", "x", {})).resolves.toBe(
      "direct:x",
    );
  });

  it("maps an entry's error to the DbError a direct call would give", async () => {
    const raw = {
      code: "42501",
      message: "not allowed",
      hint: "TAGS_FORBIDDEN",
    };

    const inner = fakeInner((call) =>
      call.fn === "tags_of" ? { error: raw } : { data: [] },
    );

    const batch = readBatch(inner);
    const call = blockCall(batch.transport, "api");

    const [tags, fields] = await together(batch.run, [
      async () => call("tags_of", {}, (value) => value),
      async () => call("fields_of", {}, (value) => value),
    ]);

    const direct = await blockCall({
      call: () => Promise.reject(Object.assign(new Error(raw.message), raw)),
    })("tags_of", {}, (value) => value);

    expect(fields).toMatchObject({ ok: true, data: [] });
    expect(tags).toEqual(direct);
    expect(tags?.ok).toBe(false);
  });

  it("reruns a skipped entry on its own", async () => {
    const inner = fakeInner((call) =>
      call.fn === "volatile" ? { skipped: true } : { data: call.fn },
    );

    const batch = readBatch(inner);

    const results = await together(batch.run, [
      () => batch.transport.call("api", "stable", {}),
      () => batch.transport.call("api", "volatile", {}),
    ]);

    expect(results).toEqual(["stable", "direct:volatile"]);
    expect(inner.call).toHaveBeenCalledWith("api", "volatile", {});
  });

  it("remembers a skipped function, so the next batch calls it direct alongside", async () => {
    const inner = fakeInner((call) =>
      call.fn === "volatile" ? { skipped: true } : { data: call.fn },
    );

    const memory = readBatchMemory();
    const first = readBatch(inner, memory);

    await together(first.run, [
      () => first.transport.call("api", "a", {}),
      () => first.transport.call("api", "volatile", {}),
    ]);

    inner.call.mockClear();

    const second = readBatch(inner, memory);

    const results = await together(second.run, [
      () => second.transport.call("api", "a", {}),
      () => second.transport.call("api", "b", {}),
      () => second.transport.call("api", "volatile", {}),
    ]);

    expect(results).toEqual(["a", "b", "direct:volatile"]);
    expect(inner.call.mock.calls.map(([, fn]) => fn).toSorted()).toEqual([
      "read_batch",
      "volatile",
    ]);
  });

  it("doesn't hold the others' next reads while a skipped read reruns", async () => {
    let releaseVolatile: () => void = () => undefined;

    const inner = {
      call: vi.fn<BlockTransport["call"]>((_schema, fn, args) => {
        if (fn === "volatile") {
          return new Promise((resolve) => {
            releaseVolatile = () => {
              resolve("direct:volatile");
            };
          });
        }

        if (fn !== "read_batch") {
          return Promise.resolve(`direct:${fn}`);
        }

        // SAFETY: the batch transport sends `{ calls }`.
        const { calls } = args as { readonly calls: readonly Batched[] };

        return Promise.resolve(
          calls.map((call) =>
            call.fn === "volatile" ? { skipped: true } : { data: call.fn },
          ),
        );
      }),
    };

    const batch = readBatch(inner);

    const done = together(batch.run, [
      () => batch.transport.call("api", "volatile", {}),
      async () => {
        await batch.transport.call("api", "a1", {});

        const second = await batch.transport.call("api", "a2", {});

        releaseVolatile();

        return second;
      },
    ]);

    await expect(done).resolves.toEqual(["direct:volatile", "direct:a2"]);
  });

  it("falls back to direct calls, and stops batching, when read_batch is missing", async () => {
    const missing = Object.assign(new Error("Could not find the function"), {
      code: "PGRST202",
    });

    const inner = fakeInner(undefined, () => Promise.reject(missing));
    const batch = readBatch(inner);

    const first = await together(batch.run, [
      () => batch.transport.call("api", "a", {}),
      () => batch.transport.call("api", "b", {}),
    ]);

    expect(first).toEqual(["direct:a", "direct:b"]);
    expect(inner.call).toHaveBeenCalledTimes(3);

    inner.call.mockClear();

    const second = await together(batch.run, [
      () => batch.transport.call("api", "a", {}),
      () => batch.transport.call("api", "b", {}),
    ]);

    expect(second).toEqual(["direct:a", "direct:b"]);
    expect(inner.call).toHaveBeenCalledTimes(2);
    expect(inner.call).not.toHaveBeenCalledWith(
      "api",
      "read_batch",
      expect.anything(),
    );
  });

  it("falls back to direct calls once when read_batch fails for another reason", async () => {
    const inner = fakeInner(undefined, () =>
      Promise.reject(Object.assign(new Error("timeout"), { code: "57014" })),
    );

    const batch = readBatch(inner);

    await together(batch.run, [
      () => batch.transport.call("api", "a", {}),
      () => batch.transport.call("api", "b", {}),
    ]);

    inner.call.mockClear();

    await together(batch.run, [
      () => batch.transport.call("api", "a", {}),
      () => batch.transport.call("api", "b", {}),
    ]);

    expect(inner.call).toHaveBeenCalledWith(
      "api",
      "read_batch",
      expect.anything(),
    );
  });

  it("sends a participant's second, dependent read in the next flush", async () => {
    const inner = fakeInner();
    const batch = readBatch(inner);

    const results = await together(batch.run, [
      async () => {
        const first = await batch.transport.call("api", "a1", {});
        const second = await batch.transport.call("api", "a2", {});

        return [first, second];
      },
      async () => {
        const first = await batch.transport.call("api", "b1", {});
        const second = await batch.transport.call("api", "b2", {});

        return [first, second];
      },
    ]);

    expect(results).toEqual([
      ["a1", "a2"],
      ["b1", "b2"],
    ]);
    expect(inner.call).toHaveBeenCalledTimes(2);
    expect(inner.call.mock.calls.map(([, fn, args]) => [fn, args])).toEqual([
      [
        "read_batch",
        {
          calls: [
            { fn: "a1", args: {} },
            { fn: "b1", args: {} },
          ],
        },
      ],
      [
        "read_batch",
        {
          calls: [
            { fn: "a2", args: {} },
            { fn: "b2", args: {} },
          ],
        },
      ],
    ]);
  });

  it("waits for a participant that hasn't read yet, and flushes once it finishes", async () => {
    const inner = fakeInner();
    const batch = readBatch(inner);

    const results = await together<unknown>(batch.run, [
      () => batch.transport.call("api", "a", {}),
      () => Promise.resolve("no read"),
    ]);

    expect(results).toEqual(["direct:a", "no read"]);
  });

  it(`splits a batch longer than ${String(READ_BATCH_LIMIT)} calls`, async () => {
    const inner = fakeInner();
    const batch = readBatch(inner);

    const count = READ_BATCH_LIMIT + 2;

    const results = await together(
      batch.run,
      Array.from(
        { length: count },
        (_, index) => () =>
          batch.transport.call("api", `f${String(index)}`, {}),
      ),
    );

    expect(results).toHaveLength(count);
    expect(inner.call).toHaveBeenCalledTimes(2);
  });
});
