import type { ChatInstance, Message } from "chat";

import {
  createMockChatInstance,
  selfMessageContract,
  threadIdContract,
} from "@chat-adapter/tests";
import { describe, expect, it, vi } from "vitest";
// oxlint-disable-next-line import/no-unassigned-import -- registers the matchers selfMessageContract uses
import "@chat-adapter/tests/setup";

import type { InboxMessage } from "../../src/blocks/inbox/types.ts";
import type { MessageFile } from "../../src/blocks/messaging/index.ts";
import type { IdentityTarget } from "../../src/core/contracts/authorization-hooks.ts";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  conversationIdOf,
  inboxAdapter,
  inboxIdentityOf,
} from "../../src/chat-sdk/index.ts";
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

    for (const id of ["note", "other", "missing", "self"]) {
      await adapter.dispatch({ conversation_id: "c1", message_id: id });
    }

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
    await adapter.markAsRead?.("inbox:c1", "m1");

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
    expect(last?.attachments[0]).toMatchObject({
      name: "a.png",
      mimeType: "image/png",
      size: 1,
      fetchMetadata: { attachmentId: "f1" },
    });
    expect(last?.attachments[0]?.fetchData).toBeUndefined();
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

  it("downloads clean files through download", async () => {
    const bytes = new ArrayBuffer(2);
    const download = vi.fn(async () => bytes);
    const { adapter } = setup({ download });
    const page = await adapter.fetchMessages("inbox:c1");
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
