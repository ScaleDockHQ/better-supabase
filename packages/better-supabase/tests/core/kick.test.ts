import { describe, expect, it, vi } from "vitest";

import { createOutbox } from "../../src/blocks/outbox/outbox.ts";
import { kicker } from "../../src/core/kick.ts";
import { silentLogger } from "../../src/core/logger.ts";

const deferred = (): { promise: Promise<void>; resolve: () => void } => {
  let resolve = (): void => undefined;

  const promise = new Promise<void>((done) => {
    resolve = done;
  });

  return { promise, resolve };
};

describe("kicker", () => {
  it("runs one pass for writes made before it starts", async () => {
    const run = vi.fn(async () => undefined);
    const kept: Promise<unknown>[] = [];

    const fire = kicker(
      { waitUntil: (work) => kept.push(work), run },
      silentLogger,
      "test",
    );

    fire("a");
    fire("a");
    fire("a");
    await Promise.all(kept);

    expect(run).toHaveBeenCalledOnce();
    expect(kept).toHaveLength(3);
  });

  it("queues one more pass for writes made while a pass runs", async () => {
    const gate = deferred();
    const run = vi.fn(async () => gate.promise);
    const kept: Promise<unknown>[] = [];

    const fire = kicker(
      { waitUntil: (work) => kept.push(work), run },
      silentLogger,
      "test",
    );

    fire("a");
    await Promise.resolve();
    await Promise.resolve();
    expect(run).toHaveBeenCalledOnce();

    fire("a");
    fire("a");
    gate.resolve();
    await Promise.all(kept);

    expect(run).toHaveBeenCalledTimes(2);
  });

  it("keeps keys apart", async () => {
    const run = vi.fn(async () => undefined);
    const kept: Promise<unknown>[] = [];

    const fire = kicker(
      { waitUntil: (work) => kept.push(work), run },
      silentLogger,
      "test",
    );

    fire("emails");
    fire("exports");
    await Promise.all(kept);

    expect(run.mock.calls).toEqual([["emails"], ["exports"]]);
  });

  it("logs a failing pass and a missing waitUntil", async () => {
    const logger = { ...silentLogger, error: vi.fn(), warn: vi.fn() };
    let work: Promise<unknown> = Promise.resolve();

    const fire = kicker(
      {
        waitUntil: (promise) => {
          work = promise;
          throw new Error("outside a request");
        },
        run: async () => {
          throw new Error("relay failed");
        },
      },
      logger,
      "outbox",
    );

    fire("outbox");
    await work;

    expect(logger.warn).toHaveBeenCalledWith(
      "outbox kick: waitUntil is unavailable",
      expect.anything(),
    );
    expect(logger.error).toHaveBeenCalledWith(
      "outbox kick failed",
      expect.anything(),
    );
  });
});

describe("kick on a block", () => {
  const outboxWith = (emitted: unknown) => {
    const kept: Promise<unknown>[] = [];

    const run = vi.fn(async () => {
      throw new Error("relay failed");
    });

    const outbox = createOutbox({
      source: "https://crm.example.com",
      transport: {
        call: async () => {
          if (emitted instanceof Error) {
            throw emitted;
          }

          return emitted;
        },
      },
      kick: { waitUntil: (work) => kept.push(work), run },
      logger: silentLogger,
    });

    return { outbox, kept, run };
  };

  it("runs after a successful emit and a throwing pass keeps the result", async () => {
    const { outbox, kept, run } = outboxWith("e1");

    const result = await outbox.emit({ type: "invoice.paid", payload: {} });
    await Promise.all(kept);

    expect(result.data).toBe("e1");
    expect(run).toHaveBeenCalledWith("outbox");
  });

  it("doesn't run after a failed emit", async () => {
    const { outbox, kept, run } = outboxWith(new Error("down"));

    const result = await outbox.emit({ type: "invoice.paid", payload: {} });

    expect(result.ok).toBe(false);
    expect(kept).toEqual([]);
    expect(run).not.toHaveBeenCalled();
  });
});
