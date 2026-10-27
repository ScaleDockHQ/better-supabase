import {
  createMockAdapter,
  createMockState,
  createTestMessage,
} from "@chat-adapter/tests";
import { describe, expect, it, vi } from "vitest";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  inboxAdapter,
  scheduledAdapter,
  stateScheduler,
} from "../../src/chat-sdk/index.ts";
import { ConformanceError, testChatAdapter } from "../../src/testing/index.ts";
import {
  conversationRow,
  fakeTransport,
  messageRow,
} from "../blocks/inbox/fixtures.ts";

const sent = { ...messageRow, id: "sent", author_type: "bot" };

function inbox() {
  let body = "conformance post";

  const { transport } = fakeTransport({
    send_inbox_message: () => ({ ...sent, body }),
    edit_inbox_message: (args: Record<string, unknown>) => {
      body = String(args["body"] ?? body);

      return { ...sent, body };
    },
    get_inbox_message: () => ({ ...sent, body }),
    list_inbox_messages: () => [{ ...sent, body }],
    start_conversation: { ...conversationRow, id: "c9" },
    list_inbox_conversations: [conversationRow],
  });

  return createInbox({ transport });
}

describe("testChatAdapter", () => {
  it("passes the inbox adapter, optional methods included", async () => {
    const adapter = scheduledAdapter(
      inboxAdapter({ inbox: inbox(), dmInbox: "i1" }),
      stateScheduler(createMockState()),
    );

    const report = await testChatAdapter(adapter, {
      threadId: "inbox:i1:c1",
      dmUserId: "ct1",
    });

    expect(report.subject).toBe('Adapter "inbox"');
    expect(report.checks.map((check) => check.name)).toEqual([
      "round-trips its thread ids",
      "posts, reads, edits and deletes a message",
      "renders formatted text",
      "opens a DM it can post to",
      "describes the thread's channel",
      "lists the channel's threads",
      "schedules a message and cancels it",
    ]);
  });

  it("reports every broken part", async () => {
    const adapter = createMockAdapter("broken", {
      encodeThreadId: () => "other",
      postMessage: vi.fn(async () => ({ id: "", threadId: "x", raw: {} })),
      renderFormatted: () => "",
      fetchChannelInfo: async () => ({ id: "other", metadata: {} }),
      listThreads: async () => ({
        threads: [
          {
            id: "a",
            rootMessage: createTestMessage("m", "x", { threadId: "b" }),
          },
        ],
      }),
      scheduleMessage: async () => ({
        scheduledMessageId: "",
        channelId: "c",
        postAt: new Date(0),
        raw: null,
        cancel: async () => {},
      }),
    });

    const failure = await testChatAdapter(adapter, {
      threadId: "broken:c:t",
    }).catch((error: unknown) => error);

    if (!(failure instanceof ConformanceError)) {
      throw new TypeError("expected a ConformanceError");
    }

    expect(failure.report.checks.filter((check) => !check.ok)).toHaveLength(6);
  });
});
