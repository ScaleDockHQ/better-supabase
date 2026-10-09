import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import {
  defineTransportMiddleware,
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../src/core/block-hooks.ts";
import { dbError } from "../../src/core/errors.ts";
import { silentLogger } from "../../src/core/logger.ts";
import { AsyncResult, type Result } from "../../src/core/result.ts";

interface Counter {
  add(by: number, label?: string): AsyncResult<{ total: number }>;
  read(): AsyncResult<{ total: number; tags: string[] }>;
  readonly name: string;
}

const counter = (): Counter & { readonly calls: unknown[][] } => {
  const calls: unknown[][] = [];
  let total = 0;
  return {
    calls,
    name: "counter",
    add(by, label) {
      calls.push([by, label]);
      total += by;
      return AsyncResult.ok({ total });
    },
    read() {
      return AsyncResult.ok({ total, tags: ["a"] });
    },
  };
};

describe("withBlockHooks", () => {
  it("returns the client unchanged without hooks", () => {
    const client = counter();
    expect(withBlockHooks(client, undefined)).toBe(client);
  });

  it("lets before rewrite the arguments", async () => {
    const client = counter();
    const hooked = withBlockHooks(client, {
      add: { before: ([by]) => [by * 10, "rewritten"] },
    });
    expect(await hooked.add(2)).toMatchObject({
      ok: true,
      data: { total: 20 },
    });
    expect(client.calls).toEqual([[20, "rewritten"]]);
    expect(hooked.name).toBe("counter");
  });

  it("refuses the call when before returns a DbError", async () => {
    const client = counter();
    const hooked = withBlockHooks(client, {
      add: {
        before: ([by]) =>
          by > 5 ? dbError("forbidden", "Too many") : undefined,
      },
    });
    const result = await hooked.add(6);
    expect(result).toMatchObject({ ok: false, error: { kind: "forbidden" } });
    expect(client.calls).toEqual([]);
    expect((await hooked.add(1)).ok).toBe(true);
  });

  it("returns an error, never throws, when before throws", async () => {
    const hooked = withBlockHooks(counter(), {
      add: {
        before: () => {
          throw new Error("boom");
        },
      },
    });
    expect(await hooked.add(1)).toMatchObject({ ok: false });
  });

  it("gives after a copy it can't change the result through", async () => {
    const after = vi.fn((result: Result<{ tags: string[] }>) => {
      if (result.ok) result.data.tags.push("mutated");
    });
    const hooked = withBlockHooks(counter(), { read: { after } });
    const result = await hooked.read();
    expect(result).toMatchObject({ ok: true, data: { total: 0, tags: ["a"] } });
    expect(after).toHaveBeenCalledWith(
      { ok: true, data: { total: 0, tags: ["a", "mutated"] }, error: null },
      [],
      { block: "block", method: "read" },
    );
  });

  it("logs an after hook that throws and keeps the result", async () => {
    const logger = { ...silentLogger, error: vi.fn() };
    const hooked = withBlockHooks(
      counter(),
      {
        add: {
          after: () => {
            throw new Error("observer");
          },
        },
      },
      { block: "counter", logger },
    );
    expect(await hooked.add(1)).toMatchObject({ ok: true, data: { total: 1 } });
    expect(logger.error).toHaveBeenCalledWith(
      "counter.add after hook threw",
      expect.objectContaining({ cause: expect.any(Error) }),
    );
  });

  it("rejects hooks for methods the client lacks", () => {
    expect(() =>
      withBlockHooks(counter(), {
        // @ts-expect-error -- not a method of the counter
        missing: { before: () => undefined },
      }),
    ).toThrow(/no method "missing"/);
  });

  it("keeps prototype methods of class clients", async () => {
    class Box {
      readonly #value = 3;
      get(): AsyncResult<number> {
        return AsyncResult.ok(this.#value);
      }
    }
    const hooked = withBlockHooks(new Box(), {
      get: { after: () => undefined },
    });
    expect(await hooked.get()).toMatchObject({ ok: true, data: 3 });
  });
});

const recording = (
  value: unknown = "done",
): BlockTransport & { readonly seen: unknown[][] } => {
  const seen: unknown[][] = [];
  return {
    seen,
    call(schema, fn, args) {
      seen.push([schema, fn, args]);
      return Promise.resolve(value);
    },
  };
};

describe("extendBlock", () => {
  it("adds methods that compose the base and call SQL", async () => {
    const transport = recording(7);
    const extended = extendBlock(
      counter(),
      (base, { call }) => ({
        addTwice: (by: number) => base.add(by).andThen(() => base.add(by)),
        archive: (id: string) => call("archive_thing", { id }, Number),
      }),
      { transport, schema: "app" },
    );
    expect(await extended.addTwice(2)).toMatchObject({
      ok: true,
      data: { total: 4 },
    });
    expect(await extended.archive("1")).toMatchObject({ ok: true, data: 7 });
    expect(transport.seen).toEqual([["app", "archive_thing", { id: "1" }]]);
    expect(extended.name).toBe("counter");
  });

  it("maps a transport rejection to a DbError", async () => {
    const transport: BlockTransport = {
      call: () =>
        Promise.reject(Object.assign(new Error("denied"), { code: "42501" })),
    };
    const extended = extendBlock(
      counter(),
      (_base, { call }) => ({ go: () => call("go", {}, () => true) }),
      { transport },
    );
    expect(await extended.go()).toMatchObject({
      ok: false,
      error: { kind: "forbidden" },
    });
  });

  it("returns an error from call without a transport", async () => {
    const extended = extendBlock(counter(), (_base, { call }) => ({
      go: () => call("go", {}, () => true),
    }));
    expect(await extended.go()).toMatchObject({
      ok: false,
      error: { kind: "unsupported" },
    });
  });

  it("refuses to redefine a base method", () => {
    expect(() =>
      extendBlock(counter(), () => ({ add: () => AsyncResult.ok(0) })),
    ).toThrow(/can't redefine "add"/);
  });
});

describe("wrapTransport", () => {
  it("runs middleware outermost first and lets it rewrite the request", async () => {
    const order: string[] = [];
    const transport = recording();
    const wrapped = wrapTransport(
      transport,
      defineTransportMiddleware({
        name: "outer",
        call: async (request, next) => {
          order.push("outer");
          return next({ ...request, args: { ...request.args, extra: 1 } });
        },
      }),
      defineTransportMiddleware({
        name: "inner",
        call: async (request, next) => {
          order.push(`inner ${String(request.args["extra"])}`);
          return next(request);
        },
      }),
    );
    expect(await wrapped.call("s", "f", { a: 1 })).toBe("done");
    expect(order).toEqual(["outer", "inner 1"]);
    expect(transport.seen).toEqual([["s", "f", { a: 1, extra: 1 }]]);
  });

  it("refuses middleware for another API version", () => {
    expect(() =>
      wrapTransport(recording(), {
        // @ts-expect-error -- a future contract
        apiVersion: 2,
        name: "future",
        call: (request, next) => next(request),
      }),
    ).toThrow(/targets API 2/);
  });
});
