import { describe, expect, it, vi } from "vitest";

import type { BlockEvent } from "../../../src/core/block-events.ts";

import { subscribeEventTriggers } from "../../../src/blocks/workflow-editor/event-triggers.ts";
import { dbError } from "../../../src/core/errors.ts";
import { EventHub } from "../../../src/core/events.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function hub() {
  const events = new EventHub({ error: () => {}, warn: () => {} } as never);

  return {
    events,
    emit: (event: unknown) => {
      events.emit("block", event as BlockEvent);
    },
  };
}

const flush = () =>
  new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });

describe("subscribeEventTriggers", () => {
  it("fires each block event with its type, data, tenant, subject and time", async () => {
    const source = hub();
    const fire = vi.fn(() => AsyncResult.ok(["wrun_1"]));
    subscribeEventTriggers(source, { triggers: { fire } as never });

    source.emit({
      type: "task.created",
      data: { id: "k" },
      tenant: "t1",
      subject: "tasks/k",
      time: { toString: () => "2026-01-01T00:00:00Z" } as never,
    });
    source.emit({
      type: "task.deleted",
      data: {},
      time: { toString: () => "2026-01-02T00:00:00Z" } as never,
    });
    await flush();

    expect(fire.mock.calls).toEqual([
      [
        {
          type: "task.created",
          data: { id: "k" },
          tenant: "t1",
          subject: "tasks/k",
          time: "2026-01-01T00:00:00Z",
        },
      ],
      [{ type: "task.deleted", data: {}, time: "2026-01-02T00:00:00Z" }],
    ]);
  });

  it("reports a failed start and a thrown one, and never throws into the emitter", async () => {
    const source = hub();
    const onError = vi.fn();
    let mode: "err" | "throw" = "err";

    const fire = vi.fn(() => {
      if (mode === "throw") {
        throw new Error("down");
      }

      return AsyncResult.err(dbError("aborted", "no start"));
    });

    subscribeEventTriggers(
      source,
      { triggers: { fire } as never },
      { onError },
    );

    const event = {
      type: "a.b",
      data: null,
      time: { toString: () => "t" } as never,
    } as never;

    expect(() => {
      source.emit(event);
    }).not.toThrow();
    await flush();
    mode = "throw";
    source.emit(event);
    await flush();

    expect(
      onError.mock.calls.map(([error, type]) => [error.message, type]),
    ).toEqual([
      ["no start", "a.b"],
      ["down", "a.b"],
    ]);

    const throwing = vi.fn(() => {
      throw new Error("reporter");
    });

    const loud = hub();
    subscribeEventTriggers(
      loud,
      { triggers: { fire } as never },
      { onError: throwing },
    );
    expect(() => {
      loud.emit(event);
    }).not.toThrow();
    await flush();
    expect(throwing).toHaveBeenCalledOnce();
  });

  it("stops listening when the returned function runs", async () => {
    const source = hub();
    const fire = vi.fn(() => AsyncResult.ok([]));
    const off = subscribeEventTriggers(source, { triggers: { fire } as never });

    off();
    source.emit({ type: "a.b", data: null, time: { toString: () => "t" } });
    await flush();
    expect(fire).not.toHaveBeenCalled();
  });
});
