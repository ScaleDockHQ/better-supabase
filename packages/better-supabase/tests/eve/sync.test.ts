import { describe, expect, it, vi } from "vitest";

import type { AiChat } from "../../src/blocks/ai-chat/ai-chat.ts";
import type { EveSyncEvent } from "../../src/eve/sync.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  createSessionSync,
  sessionChatId,
  sweepSessions,
  syncSession,
} from "../../src/eve/sync.ts";
import { memoryStore } from "./memory-store.ts";

interface Call {
  readonly fn: string;
  readonly args: unknown[];
}

function fakeChats(
  options: { readonly steps?: unknown[]; readonly runs?: unknown[] } = {},
) {
  const calls: Call[] = [];

  const record =
    <T>(fn: string, value: T) =>
    (...args: unknown[]) => {
      calls.push({ fn, args });

      return AsyncResult.ok(value);
    };

  const chats = {
    chats: {
      create: record("chats.create", { id: "c" }),
      get: record("chats.get", { id: "c", leafId: "m0", activeRunId: "run_1" }),
    },
    messages: {
      appendUser: record("messages.appendUser", {}),
      saveAssistant: record("messages.saveAssistant", {}),
    },
    runs: {
      claim: record("runs.claim", { runId: "run_1" }),
      release: record("runs.release", true),
      list: record("runs.list", options.runs ?? []),
      steps: {
        record: record("steps.record", {}),
        list: record("steps.list", options.steps ?? []),
      },
    },
    approvals: {
      request: record("approvals.request", {}),
      decide: record("approvals.decide", {}),
    },
    inputs: {
      open: record("inputs.open", { id: "in_1" }),
      answer: record("inputs.answer", {}),
    },
  };

  // SAFETY: the fake implements the calls the sync makes.
  return { chats: chats as unknown as AiChat, calls };
}

const at = (
  line: number,
  type: string,
  data: unknown,
  turnId?: string,
): EveSyncEvent => ({
  type,
  data,
  ...(turnId === undefined ? {} : { scope: { turnId } }),
  meta: { position: { line, index: 0 } },
});

const admitted = at(1, "delivery.admitted", {
  deliveryId: "d1",
  principal: { id: "user-1", type: "user" },
});

const reader = (events: readonly EveSyncEvent[]) =>
  async function* reader(_id: string, from: number) {
    for (const event of events) {
      if ((event.meta?.position?.line ?? 0) >= from) {
        yield event;
      }
    }
  };

const target = { organizationId: "org-1", ownerId: "user-1", title: "Help" };

describe("syncSession", () => {
  it("copies a turn into the chat tables and moves the cursor", async () => {
    const { chats, calls } = fakeChats();
    const store = memoryStore();

    const events = [
      at(0, "session.started", {}),
      admitted,
      at(2, "turn.started", { turnId: "t1" }, "t1"),
      at(
        3,
        "delivery.consumed",
        { deliveryId: "d1", parts: [{ kind: "text", text: "hi" }] },
        "t1",
      ),
      at(
        4,
        "content.completed",
        { partId: "p", runId: "r", kind: "text", value: "yo", phase: "reply" },
        "t1",
      ),
      at(5, "turn.settled", { outcome: "completed" }, "t1"),
    ];

    const result = await syncSession(
      { store, chats, read: reader(events), resolve: () => target },
      "sess_1",
    );

    expect(result).toMatchObject({ status: "synced", events: 6, cursor: 6 });
    expect(calls.map((call) => call.fn)).toEqual([
      "chats.create",
      "runs.list",
      "runs.claim",
      "messages.appendUser",
      "chats.get",
      "messages.saveAssistant",
      "runs.release",
    ]);
    expect(store.cursorOf("sess_1")).toBe(6);
  });

  it("hands each reply, never an interim part, to reply with a stable key", async () => {
    const { chats } = fakeChats();
    const reply = vi.fn();

    const events = [
      at(0, "session.started", {}),
      admitted,
      at(2, "turn.started", { turnId: "t1" }, "t1"),
      at(
        3,
        "content.completed",
        { partId: "a", kind: "text", value: "thinking", phase: "commentary" },
        "t1",
      ),
      at(
        4,
        "content.completed",
        { partId: "b", kind: "text", value: "done", phase: "reply" },
        "t1",
      ),
    ];

    await syncSession(
      {
        store: memoryStore(),
        chats,
        read: reader(events),
        resolve: () => target,
        reply,
      },
      "sess_1",
    );

    expect(reply).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({
        sessionId: "sess_1",
        turnId: "t1",
        key: "t1:b",
        text: "done",
        principal: { id: "user-1", type: "user" },
      }),
    );
  });

  it("reads on from the stored cursor", async () => {
    const { chats } = fakeChats();
    const store = memoryStore();
    const events = [at(0, "session.started", {}), admitted];

    const options = {
      store,
      chats,
      read: reader(events),
      resolve: () => target,
    };

    await syncSession(options, "s");
    const again = await syncSession(options, "s");
    expect(again.events).toBe(0);
  });

  it("answers busy while another job holds the lease", async () => {
    const { chats } = fakeChats();
    const store = memoryStore();
    await store.lease("s");

    const result = await syncSession(
      { store, chats, read: reader([]), resolve: () => target },
      "s",
    );

    expect(result.status).toBe("busy");
  });

  it("frees the lease and keeps the cursor when a write fails", async () => {
    const { chats } = fakeChats();
    const store = memoryStore();

    const failing = {
      ...chats,
      chats: {
        ...chats.chats,
        create: () => AsyncResult.err(dbError("network", "down")),
      },
    } as unknown as AiChat;

    await expect(
      syncSession(
        {
          store,
          chats: failing,
          read: reader([admitted]),
          resolve: () => target,
        },
        "s",
      ),
    ).rejects.toThrow("down");
    expect(store.cursorOf("s")).toBe(0);
    expect(await store.lease("s")).toBeDefined();
  });

  it("leaves a line without its last record for the next pass", async () => {
    const { chats } = fakeChats();
    const store = memoryStore();

    const events: EveSyncEvent[] = [
      at(0, "session.started", {}),
      {
        ...at(1, "turn.started", { turnId: "t" }, "t"),
        meta: { position: { line: 1, index: 0 }, endOfLine: false },
      },
    ];

    const result = await syncSession(
      { store, chats, read: reader(events), resolve: () => target },
      "s",
    );

    expect(result).toMatchObject({ events: 1, cursor: 1 });
  });

  it("skips a session the resolver leaves out", async () => {
    const { chats, calls } = fakeChats();
    const store = memoryStore();

    const result = await syncSession(
      { store, chats, read: reader([admitted]), resolve: () => undefined },
      "s",
    );

    expect(result.status).toBe("skipped");
    expect(calls).toEqual([]);
  });

  it("ends the session on session.ended", async () => {
    const { chats } = fakeChats();
    const store = memoryStore();

    await syncSession(
      {
        store,
        chats,
        read: reader([admitted, at(2, "session.ended", { outcome: "failed" })]),
        resolve: () => target,
      },
      "s",
    );

    expect(store.statusOf("s")).toBe("failed");
  });

  it("opens an approval once and decides it from the settled interaction", async () => {
    const { chats, calls } = fakeChats({
      steps: [
        {
          key: "interaction:i1",
          detail: { kind: "approval", approvalId: "ap" },
        },
      ],
    });

    const events = [
      admitted,
      at(2, "turn.started", { turnId: "t" }, "t"),
      at(
        3,
        "interaction.opened",
        {
          interactionId: "i1",
          request: { kind: "approval" },
          origin: { call: { name: "pay", callId: "c1", input: { a: 1 } } },
        },
        "t",
      ),
      at(
        4,
        "interaction.settled",
        { interactionId: "i1", outcome: "accepted" },
        "t",
      ),
    ];

    await syncSession(
      {
        store: memoryStore(),
        chats,
        read: reader(events),
        resolve: () => target,
      },
      "s",
    );

    const names = calls.map((call) => call.fn);
    expect(names).toContain("approvals.request");
    expect(names).toContain("approvals.decide");
    expect(
      calls.find((call) => call.fn === "approvals.decide")?.args[0],
    ).toMatchObject({ approved: true });
  });

  it("opens a question input and stores its id in a step", async () => {
    const { chats, calls } = fakeChats();

    const events = [
      admitted,
      at(2, "turn.started", { turnId: "t" }, "t"),
      at(
        3,
        "interaction.opened",
        {
          interactionId: "q1",
          request: { kind: "question", prompt: "Which?" },
        },
        "t",
      ),
    ];

    await syncSession(
      {
        store: memoryStore(),
        chats,
        read: reader(events),
        resolve: () => target,
      },
      "s",
    );

    expect(calls.find((call) => call.fn === "inputs.open")).toBeDefined();
    expect(
      calls.some(
        (call) =>
          call.fn === "steps.record" &&
          JSON.stringify(call.args[0]).includes('"inputId":"in_1"'),
      ),
    ).toBe(true);
  });

  it("records one usage entry per model call, in micro-USD", async () => {
    const { chats } = fakeChats();
    const recorded: unknown[] = [];

    const usage = {
      client: {
        recordMany: (input: unknown) => {
          recorded.push(input);

          return AsyncResult.ok({});
        },
      },
      meters: { inputTokens: "in", outputTokens: "out", costMicroUsd: "cost" },
    };

    const events = [
      admitted,
      at(2, "usage.recorded", {
        kind: "model",
        usage: { inputTokens: 10, outputTokens: 5, costUsd: 0.0021 },
      }),
    ];

    await syncSession(
      {
        store: memoryStore(),
        chats,
        read: reader(events),
        resolve: () => target,
        // SAFETY: the fake implements recordMany.
        usage: usage as never,
      },
      "s",
    );

    expect(recorded).toHaveLength(1);
    expect(recorded[0]).toMatchObject({
      organizationId: "org-1",
      idempotencyKey: "eve:s:2:0",
      entries: [
        { meter: "in", quantity: 10 },
        { meter: "out", quantity: 5 },
        { meter: "cost", quantity: 2100 },
      ],
    });
  });
});

describe("syncSession replay", () => {
  it("opens no second run for a turn that already ended", async () => {
    const { chats, calls } = fakeChats({
      runs: [{ id: "run_old", streamId: "eve:s:t1", status: "completed" }],
    });

    const events = [
      admitted,
      at(2, "turn.started", { turnId: "t1" }, "t1"),
      at(3, "turn.settled", { outcome: "completed" }, "t1"),
    ];

    await syncSession(
      {
        store: memoryStore(),
        chats,
        read: reader(events),
        resolve: () => target,
      },
      "s",
    );

    const names = calls.map((call) => call.fn);
    expect(names).not.toContain("runs.claim");
    expect(names).not.toContain("runs.release");
  });
});

describe("sweepSessions", () => {
  it("syncs every session that is behind", async () => {
    const { chats } = fakeChats();
    const store = memoryStore();
    await store.wake("a");
    await store.wake("b");

    const synced = await sweepSessions({
      store,
      chats,
      read: reader([admitted]),
      resolve: () => target,
    });

    expect(synced).toBe(2);
    expect(await store.behind()).toEqual([]);
  });
});

describe("createSessionSync", () => {
  it("exposes the queue and a job handler", async () => {
    const { chats } = fakeChats();
    const store = memoryStore();

    const sync = createSessionSync({
      store,
      chats,
      read: reader([admitted]),
      resolve: () => target,
    });

    expect(sync.queue).toBe("eve_session_sync");
    await sync.job({ sessionId: "s" });
    expect(store.cursorOf("s")).toBe(2);
  });
});

describe("sessionChatId", () => {
  it("maps a session to the same chat every time", async () => {
    expect(await sessionChatId("s")).toBe(await sessionChatId("s"));
    expect(await sessionChatId("s")).not.toBe(await sessionChatId("t"));
  });
});
