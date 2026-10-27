import type { Adapter } from "chat";

import { createMockAdapter, createMockState } from "@chat-adapter/tests";
import { describe, expect, it, vi } from "vitest";

import { scheduledAdapter, stateScheduler } from "../../src/chat-sdk/index.ts";

const HOUR = 3_600_000;

function setup(adapter: Adapter = createMockAdapter("slack")) {
  const state = createMockState();
  const scheduler = stateScheduler(state, { maxAttempts: 2 });

  const chat = {
    getAdapter: (name: string) => (name === adapter.name ? adapter : undefined),
  };

  return { state, scheduler, chat, adapter };
}

describe("stateScheduler", () => {
  it("holds a message until it is due, then posts it once", async () => {
    const postMessage = vi.fn(async () => ({
      id: "p",
      threadId: "t",
      raw: {},
    }));

    const { scheduler, chat, adapter, state } = setup(
      createMockAdapter("slack", { postMessage }),
    );

    const postAt = new Date(Date.now() + HOUR);

    const scheduled = await scheduler.schedule({
      adapter,
      threadId: "slack:C1:1",
      message: { markdown: "later" },
      postAt,
    });

    expect(scheduled).toMatchObject({
      channelId: "slack:C1",
      postAt,
      raw: { adapter: "slack", threadId: "slack:C1:1", attempts: 0 },
    });
    expect(await scheduler.publishDue(chat)).toEqual({
      published: 0,
      failed: 0,
      dropped: 0,
    });

    const later = new Date(Date.now() + 2 * HOUR);
    expect(await scheduler.publishDue(chat, { now: later })).toEqual({
      published: 1,
      failed: 0,
      dropped: 0,
    });
    expect(postMessage).toHaveBeenCalledWith("slack:C1:1", {
      markdown: "later",
    });
    expect(await scheduler.publishDue(chat, { now: later })).toMatchObject({
      published: 0,
    });
    expect(await state.get("chat:scheduled")).toEqual([]);
  });

  it("lists, cancels and limits posts soonest first", async () => {
    const { scheduler, chat, adapter } = setup();
    const at = (hours: number) => new Date(Date.now() + hours * HOUR);
    const input = { adapter, threadId: "slack:C1:1", message: "x" };

    const late = await scheduler.schedule({ ...input, postAt: at(3) });
    const soon = await scheduler.schedule({ ...input, postAt: at(1) });
    const middle = await scheduler.schedule({ ...input, postAt: at(2) });

    expect((await scheduler.pending()).map((post) => post.id)).toEqual([
      soon.scheduledMessageId,
      middle.scheduledMessageId,
      late.scheduledMessageId,
    ]);

    await middle.cancel();
    expect(await scheduler.cancel(middle.scheduledMessageId)).toBe(false);
    expect(
      await scheduler.publishDue(chat, { now: at(4), limit: 1 }),
    ).toMatchObject({ published: 1 });
    expect((await scheduler.pending()).map((post) => post.id)).toEqual([
      late.scheduledMessageId,
    ]);
  });

  it("rejects a time that is not in the future", async () => {
    const { scheduler, adapter } = setup();
    const input = { adapter, threadId: "slack:C1:1", message: "x" };

    await expect(
      scheduler.schedule({ ...input, postAt: new Date(Date.now() - 1) }),
    ).rejects.toThrow("postAt must be in the future");
    await expect(
      scheduler.schedule({ ...input, postAt: new Date(Number.NaN) }),
    ).rejects.toThrow("postAt must be in the future");
  });

  it("retries a failing post, then drops it", async () => {
    const adapter = createMockAdapter("slack", {
      postMessage: vi.fn().mockRejectedValue(new Error("down")),
    });

    const { scheduler, chat } = setup(adapter);
    const later = new Date(Date.now() + 2 * HOUR);

    await scheduler.schedule({
      adapter,
      threadId: "slack:C1:1",
      message: "x",
      postAt: new Date(Date.now() + HOUR),
    });

    expect(await scheduler.publishDue(chat, { now: later })).toEqual({
      published: 0,
      failed: 1,
      dropped: 0,
    });
    expect((await scheduler.pending())[0]?.attempts).toBe(1);
    expect(await scheduler.publishDue(chat, { now: later })).toEqual({
      published: 0,
      failed: 0,
      dropped: 1,
    });
    expect(await scheduler.pending()).toEqual([]);
  });

  it("drops a post whose adapter is gone", async () => {
    const { scheduler, adapter } = setup();

    await scheduler.schedule({
      adapter,
      threadId: "slack:C1:1",
      message: "x",
      postAt: new Date(Date.now() + HOUR),
    });

    expect(
      await scheduler.publishDue(
        { getAdapter: () => undefined },
        { now: new Date(Date.now() + 2 * HOUR) },
      ),
    ).toEqual({ published: 0, failed: 0, dropped: 1 });
  });

  it("waits for the lock, then gives up", async () => {
    const state = createMockState();
    const scheduler = stateScheduler(state, { key: "k", lockWaitMs: 60 });
    const held = await state.acquireLock("k", 10_000);

    await expect(scheduler.pending()).resolves.toEqual([]);
    await expect(scheduler.cancel("x")).rejects.toThrow('"k" stayed locked');

    if (held) {
      setTimeout(() => void state.releaseLock(held), 20);
    }

    await expect(stateScheduler(state, { key: "k" }).cancel("x")).resolves.toBe(
      false,
    );
  });
});

describe("scheduledAdapter", () => {
  it("gives an adapter scheduleMessage through the scheduler", async () => {
    const { scheduler, chat } = setup();
    const adapter = scheduledAdapter(createMockAdapter("slack"), scheduler);
    const postAt = new Date(Date.now() + HOUR);

    const scheduled = await adapter.scheduleMessage("slack:C1:1", "hi", {
      postAt,
    });

    expect(scheduled.raw).toMatchObject({ adapter: "slack", message: "hi" });
    expect(
      await scheduler.publishDue(
        { getAdapter: () => adapter },
        { now: new Date(Date.now() + 2 * HOUR) },
      ),
    ).toMatchObject({ published: 1 });
    expect(chat.getAdapter("slack")).toBeDefined();
  });
});
