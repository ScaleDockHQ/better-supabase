// oxlint-disable-next-line import/no-unassigned-import -- registers the matchers selfMessageContract uses
import "@chat-adapter/tests/setup";
import {
  createMockChatInstance,
  selfMessageContract,
  threadIdContract,
} from "@chat-adapter/tests";
import { describe, expect, it, vi } from "vitest";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import { conversationIdOf, inboxAdapter } from "../../src/chat-sdk/index.ts";
import { postgresStreamStore } from "../../src/streams/index.ts";
import {
  AT,
  conversationRow,
  fakeTransport,
  messageRow,
} from "../blocks/inbox/fixtures.ts";
import { fakeStreamsTransport } from "../streams/fakes.ts";

const messages: Record<string, unknown> = {
  m1: messageRow,
  self: { ...messageRow, id: "self", author_type: "bot", author_id: null },
  note: { ...messageRow, id: "note", kind: "note" },
  other: { ...messageRow, id: "other", conversation_id: "c2" },
};

const answers = {
  get_message: (args: Record<string, unknown>) =>
    messages[String(args["message"])] ?? null,
  send_message: ({ input }: { input: Record<string, unknown> }) => ({
    ...messageRow,
    id: "sent",
    author_type: "bot",
    direction: "outbound",
    body: input["body"],
    format: input["format"],
    metadata: input["metadata"],
  }),
  edit_message: { ...messageRow, body: "edited", edited_at: AT },
  remove_message: true,
  react_to_message: {},
  set_typing: true,
  mark_conversation_read: AT,
  get_conversation: conversationRow,
  list_messages: [
    { ...messageRow, id: "a", created_at: "2026-01-01T00:00:00Z" },
    { ...messageRow, id: "b", kind: "note" },
    {
      ...messageRow,
      id: "c",
      format: "markdown",
      body: "**hi**",
      author_type: "system",
      edited_at: AT,
      metadata: { author_name: "Ops" },
      attachments: [
        {
          url: "https://x.test/a.png",
          content_type: "image/png",
          name: "a.png",
          size: 1,
        },
        { url: "https://x.test/v.mp4", content_type: "video/mp4" },
        { url: "https://x.test/s.mp3", content_type: "audio/mpeg" },
        { url: "https://x.test/f.pdf" },
        { path: "private/only.pdf" },
      ],
    },
  ],
};

function setup(options: { verify?: boolean; streams?: boolean } = {}) {
  const { transport, call } = fakeTransport(answers);
  const adapter = inboxAdapter({
    inbox: createInbox({ transport }),
    userName: "helper",
    ...(options.verify === undefined
      ? {}
      : { verify: () => options.verify === true }),
    ...(options.streams
      ? {
          streams: postgresStreamStore({
            transport: fakeStreamsTransport().transport,
            pollMs: 5,
          }),
        }
      : {}),
  });
  const chat = createMockChatInstance();
  return { adapter, chat, call };
}

const job = (message: string, conversation = "c1") =>
  new Request("https://app.test/bot", {
    method: "POST",
    body: JSON.stringify({
      conversation_id: conversation,
      message_id: message,
    }),
  });

threadIdContract({
  name: "inbox",
  encode: (id: string) =>
    inboxAdapter({
      inbox: createInbox({ transport: fakeTransport({}).transport }),
    }).encodeThreadId(id),
  decode: (id) => conversationIdOf(id),
  cases: [{ decoded: "c1", encoded: "inbox:c1" }],
});

selfMessageContract({
  name: "inbox",
  setup: async () => {
    const { adapter, chat } = setup({ verify: true });
    await adapter.initialize(chat);
    return { adapter, chat };
  },
  makeOtherMessageRequest: () => job("m1"),
  makeSelfMessageRequest: () => job("self"),
});

describe("inboxAdapter", () => {
  it("rejects bad thread ids", () => {
    expect(() => conversationIdOf("slack:c1")).toThrow(
      /not an inbox thread id/,
    );
    expect(() => conversationIdOf("inbox:")).toThrow(/not an inbox thread id/);
  });

  it("guards its webhook", async () => {
    const closed = setup();
    expect((await closed.adapter.handleWebhook(job("m1"))).status).toBe(401);
    const denied = setup({ verify: false });
    expect((await denied.adapter.handleWebhook(job("m1"))).status).toBe(401);
    const open = setup({ verify: true });
    await open.adapter.initialize(open.chat);
    const bad = (body: string) =>
      open.adapter.handleWebhook(
        new Request("https://app.test", { method: "POST", body }),
      );
    expect((await bad("nope")).status).toBe(400);
    expect((await bad("{}")).status).toBe(400);
  });

  it("dispatches only the conversation's contact messages", async () => {
    const { adapter, chat } = setup();
    await expect(
      adapter.dispatch({ conversation_id: "c1", message_id: "m1" }),
    ).rejects.toThrow(/initialize/);
    await adapter.initialize(chat);
    const processMessage = vi.spyOn(chat, "processMessage");
    for (const id of ["note", "other", "missing", "self"])
      await adapter.dispatch({ conversation_id: "c1", message_id: id });
    expect(processMessage).not.toHaveBeenCalled();
    await adapter.dispatch({ conversation_id: "c1", message_id: "m1" });
    expect(processMessage).toHaveBeenCalledWith(
      adapter,
      "inbox:c1",
      expect.anything(),
    );
  });

  it("posts, edits, deletes and reacts as the bot", async () => {
    const { adapter, call } = setup();
    const posted = await adapter.postMessage("inbox:c1", {
      markdown: "**hi**",
    });
    expect(posted).toMatchObject({ id: "sent", threadId: "inbox:c1" });
    await adapter.postMessage("inbox:c1", "plain");
    await adapter.postMessage("inbox:c1", { raw: "raw" });
    await adapter.postMessage("inbox:c1", {
      ast: {
        type: "root",
        children: [
          { type: "paragraph", children: [{ type: "text", value: "ast" }] },
        ],
      },
    });
    await adapter.editMessage("inbox:c1", "m1", "edited");
    await adapter.deleteMessage("inbox:c1", "m1");
    await adapter.addReaction("inbox:c1", "m1", "thumbs_up");
    await adapter.removeReaction("inbox:c1", "m1", "👍");
    await adapter.startTyping("inbox:c1");
    await adapter.endTyping?.("inbox:c1");
    await adapter.markAsRead?.("inbox:c1");
    const sends = call.mock.calls
      .filter(([, fn]) => fn === "send_message")
      .map(([, , args]) => args["input"]);
    expect(sends.map((args) => [args["body"], args["format"]])).toEqual([
      ["**hi**", "markdown"],
      ["plain", "text"],
      ["raw", "text"],
      ["ast", "markdown"],
    ]);
    expect(sends[0]).toMatchObject({
      author_type: "bot",
      metadata: { author_name: "helper" },
    });
    const reacts = call.mock.calls
      .filter(([, fn]) => fn === "react_to_message")
      .map(([, , args]) => args);
    expect(reacts).toMatchObject([
      { present: true, actor: "helper" },
      { emoji: "👍", present: false },
    ]);
    const typing = call.mock.calls
      .filter(([, fn]) => fn === "set_typing")
      .map(([, , args]) => args["typing"]);
    expect(typing).toEqual([true, false]);
  });

  it("reads messages and threads", async () => {
    const { adapter } = setup();
    expect(await adapter.fetchMessage?.("inbox:c1", "other")).toBeNull();
    const one = await adapter.fetchMessage?.("inbox:c1", "m1");
    expect(one?.author).toMatchObject({
      userName: "visitor",
      isBot: false,
      isMe: false,
    });
    const page = await adapter.fetchMessages("inbox:c1", {
      limit: 3,
      cursor: AT,
    });
    expect(page.messages.map((message) => message.id)).toEqual(["a", "c"]);
    expect(page.nextCursor).toBe(AT);
    const last = page.messages[1];
    expect(last?.author).toMatchObject({
      userName: "Ops",
      isBot: true,
      isSystem: true,
    });
    expect(last?.metadata.edited).toBe(true);
    expect(last?.attachments.map((file) => file.type)).toEqual([
      "image",
      "video",
      "audio",
      "file",
    ]);
    expect(
      (await adapter.fetchMessages("inbox:c1")).nextCursor,
    ).toBeUndefined();
    const thread = await adapter.fetchThread("inbox:c1");
    expect(thread).toMatchObject({
      isDM: true,
      metadata: { inboxId: "i1", botMode: "bot" },
    });
    expect(adapter.renderFormatted({ type: "root", children: [] })).toBe("");
    expect(adapter.isDM?.("inbox:c1")).toBe(true);
    expect(adapter.channelIdFromThreadId("inbox:c1")).toBe("inbox");
  });

  it("streams a reply and posts it", async () => {
    async function* source() {
      yield "Hel";
      yield { type: "markdown_text" as const, text: "lo" };
      yield {
        type: "task_update" as const,
        id: "t",
        title: "x",
        status: "complete" as const,
      };
    }
    const plain = setup();
    const posted = await plain.adapter.stream?.("inbox:c1", source());
    expect(posted?.raw.body).toBe("Hello");

    const stored = setup({ streams: true });
    const resumable = await stored.adapter.stream?.("inbox:c1", source());
    expect(resumable?.raw.metadata["stream_id"]).toMatch(/^inbox:c1:/);

    async function* empty() {
      yield " ";
    }
    expect(await plain.adapter.stream?.("inbox:c1", empty())).toBeNull();

    const controller = new AbortController();
    controller.abort();
    expect(
      await plain.adapter.stream?.("inbox:c1", source(), {
        signal: controller.signal,
      }),
    ).toBeNull();
  });

  it("sends nothing for an unknown thread", async () => {
    const { adapter } = setup();
    await expect(adapter.postMessage("slack:x", "hi")).rejects.toThrow(
      /not an inbox thread id/,
    );
  });
});
