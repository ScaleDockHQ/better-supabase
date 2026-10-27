import type { CardElement, ChatInstance, Message } from "chat";

import {
  createMockChatInstance,
  selfMessageContract,
  threadIdContract,
} from "@chat-adapter/tests";
import { describe, expect, it, vi } from "vitest";

import type { InboxMessage } from "../../src/blocks/inbox/types.ts";
import type { MessageFile } from "../../src/blocks/messaging/index.ts";
import type { IdentityTarget } from "../../src/core/contracts/authorization-hooks.ts";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  chatErrorOf,
  conversationIdOf,
  decodeInboxThreadId,
  inboxAdapter,
  inboxIdentityOf,
} from "../../src/chat-sdk/index.ts";
import { dbError } from "../../src/core/errors.ts";
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
  get_inbox_message: (args: Record<string, unknown>) =>
    messages[String(args["message"])] ?? null,
  send_inbox_message: ({ input }: { input: Record<string, unknown> }) => ({
    ...messageRow,
    id: "sent",
    author_type: "bot",
    direction: "outbound",
    body: input["body"],
    format: input["format"],
    metadata: input["metadata"],
  }),
  edit_inbox_message: { ...messageRow, body: "edited", edited_at: AT },
  remove_message: true,
  react_to_inbox_message: [],
  set_typing: true,
  mark_conversation_read: AT,
  get_conversation: conversationRow,
  list_inbox_messages: [
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
          id: "f1",
          name: "a.png",
          mimeType: "image/png",
          size: 1,
          status: "clean",
        },
        { id: "f2", name: "v.mp4", mimeType: "video/mp4", status: "clean" },
        { id: "f3", name: "s.mp3", mimeType: "audio/mpeg", status: "clean" },
        { id: "f4", name: "f.pdf", size: null, status: "clean" },
        { id: "f5", name: "scan.pdf", status: "pending" },
      ],
    },
  ],
};

function setup(
  options: {
    verify?: boolean;
    streams?: boolean;
    download?: (file: MessageFile) => Promise<ArrayBuffer>;
  } = {},
) {
  const { transport, call } = fakeTransport(answers);

  const adapter = inboxAdapter({
    inbox: createInbox({ transport }),
    userName: "helper",
    ...(options.download === undefined ? {} : { download: options.download }),
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
  encode: (thread: { inboxId: string; conversationId: string }) =>
    inboxAdapter({
      inbox: createInbox({ transport: fakeTransport({}).transport }),
    }).encodeThreadId(thread),
  decode: decodeInboxThreadId,
  cases: [
    {
      decoded: { inboxId: "i1", conversationId: "c1" },
      encoded: "inbox:i1:c1",
    },
  ],
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
    expect(() => conversationIdOf("inbox:c1")).toThrow(
      expect.objectContaining({ code: "INVALID_THREAD_ID" }),
    );
    expect(() => conversationIdOf("inbox:i1:")).toThrow(
      /not an inbox thread id/,
    );
    expect(conversationIdOf("inbox:i1:c1")).toBe("c1");
  });

  it("maps database errors to Chat SDK errors", () => {
    expect(chatErrorOf(dbError("not_found", "gone"))).toMatchObject({
      code: "NOT_FOUND",
      message: "gone",
      cause: { kind: "not_found" },
    });
    expect(
      chatErrorOf(dbError("rate_limited", "slow", { retryAfter: 2 })),
    ).toMatchObject({ code: "RATE_LIMITED", retryAfterMs: 2000 });
    expect(chatErrorOf(dbError("quota_exceeded", "used up"))).toMatchObject({
      code: "RATE_LIMITED",
      retryAfterMs: undefined,
    });
    expect(chatErrorOf(dbError("unsupported", "no"))).toMatchObject({
      code: "NOT_IMPLEMENTED",
    });
    expect(chatErrorOf(dbError("forbidden", "no"))).toMatchObject({
      code: "PERMISSION_DENIED",
    });
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

    for (const id of ["note", "other", "missing", "self"]) {
      await adapter.dispatch({ conversation_id: "c1", message_id: id });
    }

    expect(processMessage).not.toHaveBeenCalled();
    await adapter.dispatch({ conversation_id: "c1", message_id: "m1" });
    expect(processMessage).toHaveBeenCalledWith(
      adapter,
      "inbox:i1:c1",
      expect.anything(),
      {},
    );
  });

  it("forwards webhook options and runs in the background with waitUntil", async () => {
    const { adapter, chat } = setup();
    await adapter.initialize(chat);
    const processMessage = vi.spyOn(chat, "processMessage");
    const waited: Promise<unknown>[] = [];

    await adapter.dispatch(
      { conversation_id: "c1", message_id: "m1", inbox_id: "i2" },
      { waitUntil: (task) => waited.push(task), deduplicate: false },
    );

    expect(waited).toHaveLength(1);
    await Promise.all(waited);
    expect(processMessage).toHaveBeenCalledWith(
      adapter,
      "inbox:i2:c1",
      expect.anything(),
      { deduplicate: false },
    );

    processMessage.mockRejectedValueOnce(new Error("handler"));
    const logged: Promise<unknown>[] = [];
    await adapter.dispatch(
      { conversation_id: "c1", message_id: "m1" },
      { waitUntil: (task) => logged.push(task) },
    );
    await expect(Promise.all(logged)).resolves.toBeDefined();

    processMessage.mockRejectedValueOnce(new Error("handler"));
    const propagated: Promise<unknown>[] = [];
    await adapter.dispatch(
      { conversation_id: "c1", message_id: "m1" },
      {
        waitUntil: (task) => propagated.push(task),
        propagateHandlerErrors: true,
      },
    );
    await expect(Promise.all(propagated)).rejects.toThrow("handler");
  });

  it("reports the concurrency scope it was given", () => {
    const { transport } = fakeTransport({});
    expect(
      inboxAdapter({ inbox: createInbox({ transport }) }),
    ).not.toHaveProperty("getConcurrencyScope");
    expect(
      inboxAdapter({
        inbox: createInbox({ transport }),
        concurrencyScope: "t1",
      }).getConcurrencyScope?.(),
    ).toBe("t1");
  });

  it("posts, edits, deletes and reacts as the bot", async () => {
    const { adapter, call } = setup();

    const posted = await adapter.postMessage("inbox:i1:c1", {
      markdown: "**hi**",
    });

    expect(posted).toMatchObject({ id: "sent", threadId: "inbox:i1:c1" });
    await adapter.postMessage("inbox:i1:c1", "plain");
    await adapter.postMessage("inbox:i1:c1", { raw: "raw" });
    await adapter.postMessage("inbox:i1:c1", {
      ast: {
        type: "root",
        children: [
          { type: "paragraph", children: [{ type: "text", value: "ast" }] },
        ],
      },
    });
    await adapter.editMessage("inbox:i1:c1", "m1", "edited");
    await adapter.deleteMessage("inbox:i1:c1", "m1");
    await adapter.addReaction("inbox:i1:c1", "m1", "thumbs_up");
    await adapter.removeReaction("inbox:i1:c1", "m1", "👍");
    await adapter.startTyping("inbox:i1:c1");
    await adapter.endTyping?.("inbox:i1:c1");
    await adapter.markAsRead?.("inbox:i1:c1", "m1");

    const sends = call.mock.calls
      .filter(([, fn]) => fn === "send_inbox_message")
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
      .filter(([, fn]) => fn === "react_to_inbox_message")
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
    expect(await adapter.fetchMessage?.("inbox:i1:c1", "other")).toBeNull();
    const one = await adapter.fetchMessage?.("inbox:i1:c1", "m1");
    expect(one?.author).toMatchObject({
      userName: "visitor",
      isBot: false,
      isMe: false,
    });

    const page = await adapter.fetchMessages("inbox:i1:c1", {
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
    expect(last?.attachments[0]).toMatchObject({
      name: "a.png",
      mimeType: "image/png",
      size: 1,
      fetchMetadata: { attachmentId: "f1" },
    });
    expect(last?.attachments[0]?.fetchData).toBeUndefined();
    expect(
      (await adapter.fetchMessages("inbox:i1:c1")).nextCursor,
    ).toBeUndefined();
    const thread = await adapter.fetchThread("inbox:i1:c1");
    expect(thread).toMatchObject({
      isDM: true,
      metadata: { inboxId: "i1", botMode: "bot" },
    });
    expect(adapter.renderFormatted({ type: "root", children: [] })).toBe("");
    expect(adapter.isDM?.("inbox:i1:c1")).toBe(true);
    expect(adapter.channelIdFromThreadId("inbox:i1:c1")).toBe("inbox:i1");
    expect(thread.channelId).toBe("inbox:i1");
    const raw = one?.raw;

    if (raw === undefined) {
      throw new Error("expected a message");
    }

    expect(adapter.parseMessage(raw).threadId).toBe("inbox:i1:c1");
    expect(() => setup().adapter.parseMessage(raw)).toThrow(/no thread seen/);
  });

  it("pages forward from a cursor", async () => {
    const { adapter, call } = setup();

    const page = await adapter.fetchMessages("inbox:i1:c1", {
      limit: 3,
      cursor: AT,
      direction: "forward",
    });

    expect(call).toHaveBeenLastCalledWith(
      expect.anything(),
      "list_inbox_messages",
      expect.objectContaining({ after: AT, max: 3 }),
    );
    expect(page.nextCursor).toBe(AT);
    await adapter.fetchMessages("inbox:i1:c1", { direction: "forward" });
    expect(call).toHaveBeenLastCalledWith(
      expect.anything(),
      "list_inbox_messages",
      expect.objectContaining({ after: "-infinity" }),
    );
  });

  it("downloads clean files through download", async () => {
    const bytes = new ArrayBuffer(2);
    const download = vi.fn(async () => bytes);
    const { adapter } = setup({ download });
    const page = await adapter.fetchMessages("inbox:i1:c1");
    const file = page.messages.at(-1)?.attachments[0];
    expect(await file?.fetchData?.()).toBe(bytes);
    expect(download).toHaveBeenCalledWith(
      expect.objectContaining({ id: "f1", status: "clean" }),
    );
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
    const posted = await plain.adapter.stream?.("inbox:i1:c1", source());
    expect(posted?.raw.body).toBe("Hello");

    const stored = setup({ streams: true });
    const resumable = await stored.adapter.stream?.("inbox:i1:c1", source());
    expect(resumable?.raw.metadata["stream_id"]).toMatch(/^inbox:c1:/);

    async function* empty() {
      yield " ";
    }

    expect(await plain.adapter.stream?.("inbox:i1:c1", empty())).toBeNull();

    const controller = new AbortController();
    controller.abort();
    expect(
      await plain.adapter.stream?.("inbox:i1:c1", source(), {
        signal: controller.signal,
      }),
    ).toBeNull();
  });

  it("sends nothing for an unknown thread", async () => {
    const { adapter } = setup();
    await expect(adapter.postMessage("slack:x", "hi")).rejects.toThrow(
      /not an inbox thread id/,
    );
    await expect(adapter.postMessage("inbox:c1", "hi")).rejects.toThrow(
      /not an inbox thread id/,
    );
  });
});

function identitySetup(target: IdentityTarget | null) {
  const { transport } = fakeTransport({
    get_inbox_message: messageRow,
    get_conversation: conversationRow,
  });

  const principalByIdentity = vi.fn(() => target);
  const ticketFor = vi.fn((userId: string) => `ticket:${userId}`);

  const adapter = inboxAdapter({
    inbox: createInbox({ transport }),
    identities: { principalByIdentity, ticketFor },
  });

  const seen: (string | undefined)[] = [];
  const messages: Message<InboxMessage>[] = [];

  const chat = {
    processMessage: (
      _adapter: unknown,
      _threadId: string,
      message: Message<InboxMessage>,
    ) => {
      seen.push(adapter.ticketOf(message));
      messages.push(message);

      return Promise.resolve();
    },
  };

  // SAFETY: dispatch only calls processMessage on the instance.
  void adapter.initialize(chat as unknown as ChatInstance);

  return { adapter, principalByIdentity, ticketFor, seen, messages };
}

const linkedJob = { conversation_id: "c1", message_id: "m1" };

describe("inboxAdapter identities", () => {
  it("runs a linked contact's message with a ticket for the user", async () => {
    const { adapter, principalByIdentity, ticketFor, seen } = identitySetup({
      kind: "user",
      userId: "u1",
    });

    await adapter.dispatch(linkedJob);
    expect(principalByIdentity).toHaveBeenCalledWith(inboxIdentityOf("ct1"));
    expect(ticketFor).toHaveBeenCalledWith("u1");
    expect(seen).toEqual(["ticket:u1"]);
  });

  it("keeps an unlinked or contact-linked author a visitor", async () => {
    for (const target of [
      null,
      { kind: "contact" as const, contactId: "ct1" },
    ]) {
      const { adapter, ticketFor, seen } = identitySetup(target);
      await adapter.dispatch(linkedJob);
      expect(ticketFor).not.toHaveBeenCalled();
      expect(seen).toEqual([undefined]);
    }
  });

  it("forgets the ticket once the handlers return", async () => {
    const { adapter, seen, messages } = identitySetup({
      kind: "user",
      userId: "u1",
    });

    await adapter.dispatch(linkedJob);
    expect(seen).toEqual(["ticket:u1"]);
    const [message] = messages;
    expect(message && adapter.ticketOf(message)).toBeUndefined();
  });
});

describe("inboxAdapter optional methods", () => {
  const second = { ...conversationRow, id: "c2", last_message_at: null };

  const extras = (dmInbox?: string) => {
    const { transport, call } = fakeTransport({
      ...answers,
      start_conversation: { ...conversationRow, id: "c9", inbox_id: "dm" },
      list_inbox_conversations: (args: Record<string, unknown>) =>
        args["filter"] !== null &&
        typeof args["filter"] === "object" &&
        "before" in args["filter"]
          ? [second]
          : [conversationRow, second],
      list_inbox_messages: (args: Record<string, unknown>) =>
        args["conversation"] === "c2" ? [] : [messageRow],
    });

    const adapter = inboxAdapter({
      inbox: createInbox({ transport }),
      ...(dmInbox === undefined ? {} : { dmInbox }),
    });

    return { adapter, call };
  };

  it("opens a bot conversation as a DM only with dmInbox", async () => {
    expect("openDM" in extras().adapter).toBe(false);
    const { adapter, call } = extras("dm");
    expect(await adapter.openDM?.("ct1")).toBe("inbox:dm:c9");
    expect(call).toHaveBeenCalledWith(
      expect.anything(),
      "start_conversation",
      expect.objectContaining({
        inbox: "dm",
        input: expect.objectContaining({ bot_mode: "bot" }),
      }),
    );
  });

  it("replies to a message and keeps cards in metadata", async () => {
    const { adapter, call } = extras();
    const card: CardElement = { type: "card", title: "Order", children: [] };
    await adapter.reply?.("inbox:i1:c1", "m1", "thanks");
    await adapter.postMessage("inbox:i1:c1", card);
    await adapter.postMessage("inbox:i1:c1", { card, fallbackText: "Order" });

    const sends = call.mock.calls
      .filter(([, fn]) => fn === "send_inbox_message")
      .map(([, , args]) => args["input"]);

    expect(sends[0]).toMatchObject({ body: "thanks", reply_to: "m1" });
    expect(sends[1]["metadata"]).toMatchObject({ card });
    expect(sends[2]["metadata"]).toMatchObject({ card });
  });

  it("describes a channel and rejects other ids", async () => {
    const { adapter } = extras();
    expect(await adapter.fetchChannelInfo?.("inbox:i1")).toEqual({
      id: "inbox:i1",
      isDM: true,
      metadata: { inboxId: "i1" },
    });
    await expect(adapter.fetchChannelInfo?.("slack:C1")).rejects.toThrow(
      "not an inbox channel id",
    );
    await expect(adapter.fetchChannelInfo?.("inbox:i1:c1")).rejects.toThrow(
      "not an inbox channel id",
    );
  });

  it("lists threads with their first message and pages on", async () => {
    const { adapter, call } = extras();
    const first = await adapter.listThreads?.("inbox:i1", { limit: 2 });

    expect(first?.threads).toHaveLength(1);
    expect(first?.threads[0]).toMatchObject({
      id: "inbox:i1:c1",
      rootMessage: { id: "m1", threadId: "inbox:i1:c1" },
    });
    expect(first?.threads[0]?.lastReplyAt).toBeInstanceOf(Date);
    expect(JSON.parse(first?.nextCursor ?? "")).toEqual({
      id: "c2",
      lastMessageAt: null,
    });

    const next = await adapter.listThreads?.("inbox:i1", {
      cursor: JSON.stringify({ id: "c1", lastMessageAt: AT }),
    });

    expect(next?.threads).toEqual([]);
    expect(next?.nextCursor).toBeUndefined();
    expect(call).toHaveBeenCalledWith(
      expect.anything(),
      "list_inbox_conversations",
      expect.objectContaining({
        filter: expect.objectContaining({ inbox_id: "i1", status: "all" }),
      }),
    );
    await expect(
      adapter.listThreads?.("inbox:i1", { cursor: "nope" }),
    ).rejects.toThrow("invalid listThreads cursor");
    await expect(
      adapter.listThreads?.("inbox:i1", { cursor: "{}" }),
    ).rejects.toThrow("invalid listThreads cursor");
  });
});
