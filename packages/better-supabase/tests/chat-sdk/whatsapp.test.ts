import { describe, expect, it, vi } from "vitest";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  ChatWindowClosedError,
  sendWithinWindowOrTemplate,
} from "../../src/chat-sdk/index.ts";
import {
  AT,
  conversationRow,
  fakeTransport,
} from "../blocks/inbox/fixtures.ts";

const at = Temporal.Instant.from(AT);

const inboxOf = (lastInbound: string | null) =>
  createInbox({
    transport: fakeTransport({
      get_conversation: { ...conversationRow, last_inbound_at: lastInbound },
    }).transport,
  });

const template = { name: "order_update", language: "en_US" };

function threadOf(withTemplate = true) {
  const post = vi.fn(async () => ({ id: "m" }));
  const sendTemplate = vi.fn(async () => ({ id: "t" }));

  return {
    post,
    sendTemplate,
    thread: {
      id: "whatsapp:1:2",
      adapter: withTemplate ? { sendTemplate } : {},
      post,
    },
  };
}

describe("sendWithinWindowOrTemplate", () => {
  it("posts the message while the window is open", async () => {
    const { thread, post, sendTemplate } = threadOf();

    const sent = await sendWithinWindowOrTemplate(thread, "hello", {
      inbox: inboxOf(AT),
      conversationId: "c1",
      template,
      now: at.add({ hours: 1 }),
    });

    expect(sent.sent).toBe("message");
    expect(post).toHaveBeenCalledWith("hello");
    expect(sendTemplate).not.toHaveBeenCalled();
  });

  it("sends the template once the window has closed", async () => {
    const { thread, post, sendTemplate } = threadOf();

    const sent = await sendWithinWindowOrTemplate(thread, "hello", {
      inbox: inboxOf(AT),
      conversationId: "c1",
      template,
      now: at.add({ hours: 25 }),
    });

    expect(sent.sent).toBe("template");
    expect(sendTemplate).toHaveBeenCalledWith("whatsapp:1:2", template);
    expect(post).not.toHaveBeenCalled();
  });

  it("fails with CHAT_WINDOW_CLOSED without a template or a sender", async () => {
    const closed = { inbox: inboxOf(null), conversationId: "c1" };

    await expect(
      sendWithinWindowOrTemplate(threadOf().thread, "hello", closed),
    ).rejects.toMatchObject({ code: "CHAT_WINDOW_CLOSED" });
    await expect(
      sendWithinWindowOrTemplate(threadOf(false).thread, "hello", {
        ...closed,
        template,
      }),
    ).rejects.toBeInstanceOf(ChatWindowClosedError);
  });
});
