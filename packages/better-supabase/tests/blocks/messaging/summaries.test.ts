import { describe, expect, it, vi } from "vitest";

import type {
  ThreadSummarizer,
  ThreadSummaryInput,
} from "../../../src/blocks/messaging/index.ts";

import { createMessaging } from "../../../src/blocks/messaging/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const summaryRow = (stale: boolean, thread: string | null = null) => ({
  id: "s1",
  tenant_id: "org",
  conversation_id: "c1",
  thread_id: thread,
  summary: "Ada ships Friday.",
  model: "anthropic/claude-sonnet-4.5",
  message_count: 2,
  through_at: AT,
  stale,
  created_at: AT,
  updated_at: AT,
});

const message = (id: string, sentAt: string | null, extra = {}) => ({
  id,
  tenant_id: "org",
  conversation_id: "c1",
  parent_id: null,
  thread_id: null,
  author_id: "u1",
  author: { id: "u1", name: "Ada", avatar_url: null },
  kind: "message",
  body: `body ${id}`,
  mentions: [],
  broadcast: false,
  reply_count: 0,
  reply_user_ids: [],
  sent_at: sentAt,
  created_at: AT,
  ...extra,
});

function recorder(summary = "New summary.") {
  const inputs: ThreadSummaryInput[] = [];

  const summarizer: ThreadSummarizer = {
    apiVersion: 1,
    summarize: async (input) => {
      inputs.push(input);

      return { summary, model: "openai/gpt-5" };
    },
  };

  return { inputs, summarizer };
}

describe("messaging summaries", () => {
  it("reads a summary by conversation or thread", async () => {
    const t = fakeTransport({
      thread_summary: (args: Record<string, unknown>) =>
        args["thread"] === "m1" ? summaryRow(true, "m1") : null,
    });

    const messaging = createMessaging({ transport: t.transport });

    expect(
      await messaging.summary({ conversationId: "c1" }).orThrow(),
    ).toBeUndefined();
    expect(t.call.mock.calls[0]?.[2]).toEqual({
      conversation: "c1",
      thread: null,
    });

    const found = await messaging.summary({ threadId: "m1" }).orThrow();
    expect(t.call.mock.calls[1]?.[2]).toEqual({
      conversation: null,
      thread: "m1",
    });
    expect(found).toMatchObject({
      organizationId: "org",
      conversationId: "c1",
      threadId: "m1",
      summary: "Ada ships Friday.",
      messageCount: 2,
      stale: true,
    });
    expect(found?.throughAt.toString()).toBe(AT);
  });

  it("returns a current summary without asking the summarizer", async () => {
    const t = fakeTransport({ thread_summary: summaryRow(false) });
    const { inputs, summarizer } = recorder();
    const messaging = createMessaging({ transport: t.transport });

    const summary = await messaging
      .summarize({ conversationId: "c1" }, summarizer)
      .orThrow();

    expect(summary.summary).toBe("Ada ships Friday.");
    expect(inputs).toHaveLength(0);
  });

  it("summarizes a stale conversation and saves through the service", async () => {
    const t = fakeTransport({
      thread_summary: summaryRow(true),
      list_messages: [
        message("m1", "2026-01-01T00:01:00Z"),
        message("m2", "2026-01-01T00:02:00Z", { kind: "note" }),
        message("m3", "2026-01-01T00:03:00Z", { deleted_at: AT }),
        message("m4", "2026-01-01T00:04:00Z", { body: "  " }),
        message("m5", "2026-01-01T00:05:00Z", {
          thread_id: "m1",
          broadcast: true,
        }),
        message("m6", "2026-01-01T00:06:00Z", { author: null }),
        message("m7", null, { scheduled_for: "2026-02-01T00:00:00Z" }),
      ],
    });

    const service = fakeTransport({
      save_thread_summary: { ...summaryRow(false), summary: "New summary." },
    });

    const { inputs, summarizer } = recorder();

    const messaging = createMessaging({
      transport: t.transport,
      service: service.transport,
    });

    const summary = await messaging
      .summarize({ conversationId: "c1" }, summarizer)
      .orThrow();

    expect(summary).toMatchObject({ summary: "New summary.", stale: false });
    expect(t.call.mock.calls[1]?.[2]).toMatchObject({
      conversation: "c1",
      max_rows: 200,
    });
    expect(inputs[0]).toMatchObject({
      organizationId: "org",
      conversationId: "c1",
      threadId: undefined,
      previous: "Ada ships Friday.",
    });
    expect(
      inputs[0]?.messages.map((m) => [m.id, m.authorName, m.body]),
    ).toEqual([
      ["m1", "Ada", "body m1"],
      ["m6", undefined, "body m6"],
    ]);
    expect(service.call.mock.calls[0]?.[1]).toBe("save_thread_summary");
    expect(service.call.mock.calls[0]?.[2]).toEqual({
      conversation: "c1",
      thread: null,
      summary: "New summary.",
      attrs: {
        messageCount: 2,
        throughAt: "2026-01-01T00:06:00Z",
        model: "openai/gpt-5",
      },
    });
  });

  it("pages through a thread and keeps the root with the newest replies", async () => {
    const first = Array.from({ length: 500 }, (_, index) =>
      message(`r${String(index)}`, "2026-01-01T00:01:00Z", { thread_id: "m1" }),
    );

    const t = fakeTransport({
      thread_summary: null,
      list_replies: (args: Record<string, unknown>) =>
        args["after"] === null
          ? first
          : [message("r500", "2026-01-01T00:09:00Z", { thread_id: "m1" })],
      get_message: message("m1", AT),
      save_thread_summary: summaryRow(false, "m1"),
    });

    const { inputs, summarizer } = recorder();
    const messaging = createMessaging({ transport: t.transport });

    await messaging
      .summarize({ threadId: "m1" }, summarizer, { maxMessages: 3 })
      .orThrow();

    expect(t.call.mock.calls[2]?.[2]).toMatchObject({
      message: "m1",
      after_id: "r499",
    });
    expect(inputs[0]?.threadId).toBe("m1");
    expect(inputs[0]?.previous).toBeUndefined();
    expect(inputs[0]?.messages.map((m) => m.id)).toEqual([
      "m1",
      "r499",
      "r500",
    ]);
    expect(t.call.mock.calls.at(-1)?.[2]).toMatchObject({
      conversation: null,
      thread: "m1",
      attrs: { messageCount: 3, throughAt: "2026-01-01T00:09:00Z" },
    });
  });

  it("summarizes again when forced and clamps maxMessages", async () => {
    const t = fakeTransport({
      thread_summary: summaryRow(false),
      list_messages: [message("m1", AT)],
      save_thread_summary: summaryRow(false),
    });

    const summarize = vi.fn(async () => ({ summary: "Again." }));

    const summarizer: ThreadSummarizer = { apiVersion: 1, summarize };

    const messaging = createMessaging({ transport: t.transport });

    await messaging
      .summarize({ conversationId: "c1" }, summarizer, {
        force: true,
        maxMessages: 0,
      })
      .orThrow();

    expect(summarize).toHaveBeenCalledOnce();
    expect(t.call.mock.calls[1]?.[2]).toMatchObject({ max_rows: 1 });
    expect(t.call.mock.calls[2]?.[2]).toMatchObject({
      attrs: { messageCount: 1, throughAt: AT },
    });
    expect(t.call.mock.calls[2]?.[2]).not.toHaveProperty("attrs.model");

    await messaging
      .summarize({ conversationId: "c1" }, summarizer, {
        force: true,
        maxMessages: 1000,
        signal: new AbortController().signal,
      })
      .orThrow();

    expect(t.call.mock.calls[4]?.[2]).toMatchObject({ max_rows: 200 });
  });

  it("fails without messages, and when the summarizer throws", async () => {
    const t = fakeTransport({
      thread_summary: null,
      list_messages: [message("m1", AT, { kind: "note" })],
    });

    const { summarizer } = recorder();
    const messaging = createMessaging({ transport: t.transport });

    const empty = await messaging.summarize(
      { conversationId: "c1" },
      summarizer,
    );

    expect(empty.ok).toBe(false);
    expect(empty.error).toMatchObject({
      kind: "invalid_input",
      code: "MESSAGING_SUMMARY_EMPTY",
    });

    const broken = createMessaging({
      transport: fakeTransport({
        thread_summary: null,
        list_messages: [message("m1", AT)],
      }).transport,
    });

    const failed = await broken.summarize(
      { conversationId: "c1" },
      {
        apiVersion: 1,
        summarize: () => Promise.reject(new Error("model down")),
      },
    );

    expect(failed.error).toMatchObject({
      kind: "unexpected",
      message: "model down",
    });
  });
});
