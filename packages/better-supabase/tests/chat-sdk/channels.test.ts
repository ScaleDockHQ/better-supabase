import {
  createMockAdapter,
  createMockState,
  createTestMessage,
} from "@chat-adapter/tests";
import { RateLimitError } from "chat";
import { describe, expect, it, vi } from "vitest";

import type { ChatLike } from "../../src/chat-sdk/index.ts";
import type { CredentialProvider } from "../../src/credentials/index.ts";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  channelAdapter,
  deliver,
  inboundHandler,
  maintain,
  webhook,
  whatsappWindowOpen,
} from "../../src/chat-sdk/index.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  AT,
  conversationRow,
  fakeTransport,
  messageRow,
  storedEventRow,
} from "../blocks/inbox/fixtures.ts";

const ref = { provider: "vault", secret: "slack" };

function provider(inbound?: boolean | "error"): CredentialProvider {
  return {
    apiVersion: 1,
    name: "fake",
    getToken: vi.fn(() => AsyncResult.ok({ token: "xoxb", headers: {} })),
    capabilities: () => ({
      userSubjects: false,
      authorization: false,
      revoke: true,
      inbound: true,
    }),
    revoke: () => AsyncResult.ok(true),
    ...(inbound === undefined
      ? {}
      : {
          verifyInbound: () =>
            inbound === "error"
              ? AsyncResult.err({
                  kind: "network",
                  message: "down",
                  status: 503,
                })
              : AsyncResult.ok(inbound),
        }),
  };
}

const post = (body: string, headers: Record<string, string> = {}) =>
  new Request("https://app.test/hooks/slack", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      cookie: "a=b",
      authorization: "x",
      ...headers,
    },
    body,
  });

function chatOf(
  webhooks: ChatLike["webhooks"] = {},
  adapters: Record<string, ReturnType<typeof createMockAdapter>> = {},
) {
  const state = createMockState();

  const chat: ChatLike = {
    webhooks,
    getAdapter: (name) => adapters[name],
    getState: () => state,
  };

  return { chat, state };
}

describe("channelAdapter", () => {
  it("builds the adapter from the stored token", async () => {
    const getToken = vi.fn(() =>
      AsyncResult.ok({ token: "xoxb", headers: {} }),
    );

    const credentials = { ...provider(), getToken };

    const built = await channelAdapter({
      credentials,
      ref,
      create: (token) => ({ token: token.token }),
    });

    expect(built).toEqual({ token: "xoxb" });
    expect(getToken).toHaveBeenCalledWith(ref, { subject: { type: "app" } });
  });

  it("reads the token again for each call through resolve", async () => {
    let n = 0;

    const getToken = vi.fn(() =>
      AsyncResult.ok({ token: `xoxb-${(n += 1)}`, headers: {} }),
    );

    const built = await channelAdapter({
      credentials: { ...provider(), getToken },
      ref,
      create: (_token, resolve) => ({ botToken: resolve }),
    });

    expect(await built.botToken()).toBe("xoxb-2");
    expect(await built.botToken()).toBe("xoxb-3");
  });
});

describe("webhook", () => {
  const stored = () =>
    fakeTransport({ store_inbound_event: { id: "e1", duplicate: false } });

  it("stores the event without credentials headers and acks", async () => {
    const { transport, call } = stored();
    const after = vi.fn();

    const handle = webhook({
      inbox: createInbox({ transport }),
      adapter: "slack",
      inboxId: "i1",
      tenant: "org",
      externalId: (body) =>
        (JSON.parse(body) as { event_id?: string }).event_id,
      after,
    });

    const response = await handle(
      post('{"event_id":"Ev1"}', { "x-slack-signature": "v0=1" }),
    );

    expect(response.status).toBe(200);
    expect(after).toHaveBeenCalledWith({ id: "e1", duplicate: false });
    const args = call.mock.calls[0]?.[2];
    expect(args).toMatchObject({
      adapter: "slack",
      external_id: "Ev1",
      inbox: "i1",
      tenant: "org",
    });
    expect(Object.keys(args?.["headers"] ?? {})).toEqual([
      "content-type",
      "x-slack-signature",
    ]);
  });

  it("passes challenges through", async () => {
    const { transport, call } = stored();
    const passthroughHandler = vi.fn(async () => new Response("challenge"));

    const handle = webhook({
      inbox: createInbox({ transport }),
      adapter: "slack",
      passthroughHandler,
    });

    expect(
      await (await handle(post('{"type":"url_verification"}'))).text(),
    ).toBe("challenge");

    const bare = webhook({
      inbox: createInbox({ transport }),
      adapter: "whatsapp",
    });

    expect((await bare(new Request("https://app.test/hooks"))).status).toBe(
      404,
    );
    expect(call).not.toHaveBeenCalled();
  });

  it("verifies before storing", async () => {
    const { transport, call } = stored();
    const inbox = createInbox({ transport });

    const status = async (options: Parameters<typeof webhook>[0]) =>
      (await webhook(options)(post("{}"))).status;

    expect(await status({ inbox, adapter: "slack", ref })).toBe(500);
    expect(
      await status({ inbox, adapter: "slack", ref, credentials: provider() }),
    ).toBe(500);
    expect(
      await status({
        inbox,
        adapter: "slack",
        ref,
        credentials: provider(false),
      }),
    ).toBe(401);
    expect(
      await status({
        inbox,
        adapter: "slack",
        ref,
        credentials: provider("error"),
      }),
    ).toBe(401);
    expect(await status({ inbox, adapter: "slack", verify: () => false })).toBe(
      401,
    );
    expect(call).not.toHaveBeenCalled();
    expect(
      await status({
        inbox,
        adapter: "slack",
        ref,
        credentials: provider(true),
      }),
    ).toBe(200);
    expect(
      await status({ inbox, adapter: "slack", verify: async () => true }),
    ).toBe(200);
  });

  it("answers 503 when the store fails", async () => {
    const { transport } = fakeTransport({});

    const handle = webhook({
      inbox: createInbox({ transport }),
      adapter: "slack",
    });

    expect((await handle(post("{}"))).status).toBe(503);
  });
});

describe("inboundHandler", () => {
  const event = (adapter: string, body = "{}") => ({
    ...storedEventRow,
    adapter,
    body,
  });

  function setup(webhooks: ChatLike["webhooks"], pending: unknown[] = []) {
    const { transport, call } = fakeTransport({
      set_inbound_event_status: true,
      set_delivery_status: 1,
      pending_inbound_events: pending,
      record_inbound: {
        conversation_id: "c1",
        message_id: "m1",
        contact_id: "ct1",
        tenant_id: "org",
        created: true,
        duplicate: false,
      },
    });

    const { chat, state } = chatOf(webhooks);
    const inbox = createInbox({ transport });

    const statuses = () =>
      call.mock.calls
        .filter(([, fn]) => fn === "set_inbound_event_status")
        .map(([, , args]) => args["status"]);

    return {
      chat,
      state,
      call,
      statuses,
      handler: inboundHandler({ chat, inbox, inboxes: { slack: "i1" } }),
    };
  }

  it("applies delivery-only events without replaying them", async () => {
    const slack = vi.fn();
    const { handler, call, statuses } = setup({ whatsapp: slack });

    const stored = {
      id: "e1",
      adapter: "twilio",
      externalId: null,
      inboxId: null,
      tenant: null,
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: "MessageSid=SM1&MessageStatus=delivered",
      attempts: 0,
      receivedAt: Temporal.Instant.from(AT),
    };

    await handler.process(stored);
    expect(slack).not.toHaveBeenCalled();
    expect(statuses()).toEqual(["processing", "processed"]);

    const update = call.mock.calls.find(
      ([, fn]) => fn === "set_delivery_status",
    )?.[2];

    expect(update).toMatchObject({
      channel: "sms",
      external_id: "SM1",
      status: "delivered",
    });
  });

  it("replays other events into Chat SDK and waits for its tasks", async () => {
    let finished = false;

    const slack = vi.fn(
      async (
        request: Request,
        options?: { waitUntil?: (task: Promise<unknown>) => void },
      ) => {
        expect(request.url).toBe("https://inbox.local/slack");
        expect(await request.text()).toBe('{"a":1}');
        options?.waitUntil?.(
          new Promise((resolve) => {
            setTimeout(resolve, 1);
          }).then(() => {
            finished = true;
          }),
        );

        return new Response("ok");
      },
    );

    const { handler, statuses } = setup({ slack }, [
      event("slack", '{"a":1}'),
      event("teams"),
      event("broken"),
    ]);

    const failing = setup({
      broken: async () => new Response("no", { status: 500 }),
    });

    const result = await handler.drain({ maxAttempts: 3 });
    expect(finished).toBe(true);
    expect(result).toEqual({ processed: 3, failed: 0 });
    expect(statuses()).toEqual([
      "processing",
      "processed",
      "processing",
      "ignored",
      "processing",
      "ignored",
    ]);
    await expect(
      failing.handler.process({
        id: "e2",
        adapter: "broken",
        externalId: null,
        inboxId: null,
        tenant: null,
        headers: {},
        body: "{}",
        attempts: 0,
        receivedAt: Temporal.Instant.from(AT),
      }),
    ).rejects.toThrow(/broken answered 500/);
    expect(failing.statuses()).toEqual(["processing", "failed"]);
  });

  it("counts failed events", async () => {
    const { handler } = setup(
      { slack: async () => new Response("no", { status: 502 }) },
      [event("slack")],
    );

    expect(await handler.drain()).toEqual({ processed: 0, failed: 1 });
  });

  it("passes propagateHandlerErrors to the adapter's webhook", async () => {
    const slack = vi.fn(async () => new Response("ok"));
    const { chat } = chatOf({ slack });

    const inbox = createInbox({
      transport: fakeTransport({
        set_inbound_event_status: true,
        pending_inbound_events: [event("slack")],
      }).transport,
    });

    await inboundHandler({ chat, inbox, inboxes: {} }).drain();
    expect(slack.mock.calls[0]).not.toHaveProperty("1.propagateHandlerErrors");

    await inboundHandler({
      chat,
      inbox,
      inboxes: {},
      propagateHandlerErrors: true,
    }).drain();
    expect(slack.mock.calls[1]).toHaveProperty(
      "1.propagateHandlerErrors",
      true,
    );
  });

  it("mirrors contact messages and skips bots and echoes", async () => {
    const { handler, call, state } = setup({});
    const thread = { id: "slack:C1:1.2", adapter: { name: "slack" } };

    const message = createTestMessage("1.3", "hi", {
      author: {
        userId: "U1",
        userName: "ada",
        fullName: "Ada",
        isBot: false,
        isMe: false,
      },
      attachments: [
        {
          type: "image",
          url: "https://files.test/a.png",
          name: "a.png",
          mimeType: "image/png",
          size: 3,
        },
        { type: "file" },
      ],
    });

    expect(await handler.mirror(thread, message)).toMatchObject({
      created: true,
    });

    const recorded = call.mock.calls.find(
      ([, fn]) => fn === "record_inbound",
    )?.[2];

    expect(recorded?.["input"]).toMatchObject({
      inbox_id: "i1",
      thread_id: "slack:C1:1.2",
      contact: { external_id: "U1", name: "Ada" },
    });

    const self = createTestMessage("1.4", "beep", {
      author: {
        userId: "B1",
        userName: "bot",
        fullName: "Bot",
        isBot: true,
        isMe: true,
      },
    });

    expect(await handler.mirror(thread, self)).toBeNull();

    const otherBot = createTestMessage("1.7", "deploy done", {
      author: {
        userId: "B2",
        userName: "ci",
        fullName: "CI",
        isBot: true,
        isMe: false,
      },
    });

    expect(await handler.mirror(thread, otherBot)).not.toBeNull();
    await state.set("better-supabase:inbox:echo:slack:1.5", true);
    expect(
      await handler.mirror(thread, createTestMessage("1.5", "echo")),
    ).toBeNull();
    await expect(
      handler.mirror(
        { id: "x", adapter: { name: "teams" } },
        createTestMessage("1.6", "hi"),
      ),
    ).rejects.toThrow(/no inbox for adapter "teams"/);
  });

  it("copies files through copyFile", async () => {
    const { transport, call } = fakeTransport({
      record_inbound: {
        conversation_id: "c1",
        message_id: "m1",
        contact_id: "ct1",
        tenant_id: "org",
        created: true,
        duplicate: false,
      },
    });

    const { chat } = chatOf();

    const copyFile = vi
      .fn()
      .mockResolvedValueOnce({ path: "org/a.png" })
      .mockResolvedValueOnce(null);

    const handler = inboundHandler({
      chat,
      inbox: createInbox({ transport }),
      inboxes: { slack: "i1" },
      copyFile,
    });

    await handler.mirror(
      { id: "t", adapter: { name: "slack" } },
      createTestMessage("1", "hi", {
        author: {
          userId: "U1",
          userName: "ada",
          fullName: "",
          isBot: false,
          isMe: false,
          email: "a@x.test",
        },
        attachments: [{ type: "image" }, { type: "file" }],
      }),
    );
    expect(copyFile).toHaveBeenCalledWith(
      { type: "image" },
      { adapter: "slack", threadId: "t" },
    );
    expect(call.mock.calls[0]?.[2]["input"]).toMatchObject({
      contact: { name: "ada", email: "a@x.test" },
      message: { files: [{ path: "org/a.png" }] },
    });
  });
});

describe("importFiles", () => {
  const pendingRow = (id: string, source: Record<string, unknown>) => ({
    id,
    tenant_id: "org",
    conversation_id: "c1",
    message_id: "m1",
    bucket: "attachments",
    object_path: `org/conversation/c1/${id}`,
    name: `${id}.png`,
    mime_type: "image/png",
    source,
  });

  function setup() {
    const { transport, call } = fakeTransport({
      pending_inbox_files: [
        pendingRow("f1", { url: "https://cdn.test/f1.png" }),
        pendingRow("f2", { url: "https://cdn.test/missing.png" }),
        pendingRow("f3", { path: "org/c1/f3.png", bucket: "inbox-files" }),
      ],
      confirm_attachment: { id: "f1", status: "clean" },
      inbox_file_failed: true,
    });

    const handler = inboundHandler({
      chat: chatOf().chat,
      inbox: createInbox({ transport }),
      inboxes: {},
    });

    const calls = (fn: string) =>
      call.mock.calls
        .filter(([, name]) => name === fn)
        .map(([, , args]) => args);

    return { handler, calls };
  }

  it("fetches each source, writes it and confirms the attachment", async () => {
    const fetch = vi.fn(async (url: string) =>
      url.endsWith("missing.png")
        ? new Response(null, { status: 404 })
        : new Response("png"),
    );

    vi.stubGlobal("fetch", fetch);

    try {
      const { handler, calls } = setup();
      const write = vi.fn(async (_file: { id: string }) => undefined);

      expect(await handler.importFiles({ write, limit: 3 })).toEqual({
        processed: 1,
        failed: 2,
      });
      expect(calls("pending_inbox_files")).toEqual([{ max: 3 }]);
      expect(write).toHaveBeenCalledOnce();
      expect(write.mock.calls[0]?.[0]).toMatchObject({
        id: "f1",
        bucket: "attachments",
        path: "org/conversation/c1/f1",
      });
      expect(calls("confirm_attachment")).toEqual([{ id: "f1" }]);
      expect(calls("inbox_file_failed")).toEqual([
        {
          attachment: "f2",
          detail: "https://cdn.test/missing.png answered 404",
        },
        { attachment: "f3", detail: "file f3 has no URL; pass read" },
      ]);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("reads through read and marks a failed write", async () => {
    const { handler, calls } = setup();
    const read = vi.fn(async (_file: unknown) => new Blob(["x"]));

    const write = vi.fn(async (file: { id: string }) => {
      if (file.id === "f2") {
        throw new Error("quota");
      }
    });

    expect(await handler.importFiles({ read, write })).toEqual({
      processed: 2,
      failed: 1,
    });
    expect(calls("pending_inbox_files")).toEqual([{ max: 50 }]);
    expect(read.mock.calls[2]?.[0]).toMatchObject({
      source: { path: "org/c1/f3.png", bucket: "inbox-files" },
    });
    expect(calls("inbox_file_failed")).toEqual([
      { attachment: "f2", detail: "quota" },
    ]);
  });
});

describe("deliver", () => {
  function setup(
    overrides: { message?: unknown; conversation?: unknown } = {},
  ) {
    const { transport, call } = fakeTransport({
      get_inbox_message:
        "message" in overrides
          ? overrides.message
          : { ...messageRow, direction: "outbound", author_type: "agent" },
      get_conversation:
        "conversation" in overrides ? overrides.conversation : conversationRow,
      record_delivery: null,
    });

    const postMessage = vi.fn(async (threadId: string) => ({
      id: "wamid.out",
      threadId,
      raw: {},
    }));

    const whatsapp = createMockAdapter("whatsapp", { postMessage });

    const twilio = createMockAdapter("twilio", {
      postMessage: vi.fn(async () => {
        throw new Error("rate limited");
      }),
    });

    const { chat, state } = chatOf({}, { whatsapp, twilio });

    const deliveries = () =>
      call.mock.calls
        .filter(([, fn]) => fn === "record_delivery")
        .map(([, , args]) => args);

    return {
      chat,
      state,
      postMessage,
      deliveries,
      inbox: createInbox({ transport }),
    };
  }

  it("posts the reply, records it and remembers the echo", async () => {
    const { chat, inbox, state, postMessage, deliveries } = setup();

    const raw = await deliver({ chat, inbox })({
      message_id: "m1",
      conversation_id: "c1",
    });

    expect(raw?.id).toBe("wamid.out");
    expect(postMessage).toHaveBeenCalledWith("whatsapp:+3100:+3199", "hi");
    expect(
      await state.get("better-supabase:inbox:echo:whatsapp:wamid.out"),
    ).toBe(true);
    expect(deliveries()).toMatchObject([
      { channel: "whatsapp", external_id: "wamid.out", status: "sent" },
    ]);
  });

  it("sends a template when the window is closed", async () => {
    const { chat, inbox, postMessage } = setup({
      message: { ...messageRow, format: "markdown", body: "**x**" },
    });

    const template = vi.fn(() => ({ raw: "template" }));
    await deliver({ chat, inbox, template })({
      message_id: "m1",
      conversation_id: "c1",
    });
    expect(postMessage).toHaveBeenCalledWith("whatsapp:+3100:+3199", {
      raw: "template",
    });

    const markdown = setup({
      message: { ...messageRow, format: "markdown", body: "**x**" },
    });

    await deliver({
      chat: markdown.chat,
      inbox: markdown.inbox,
      template: () => null,
    })({ message_id: "m1", conversation_id: "c1" });
    expect(markdown.postMessage).toHaveBeenCalledWith("whatsapp:+3100:+3199", {
      markdown: "**x**",
    });
  });

  it("records a failed post and rethrows", async () => {
    const { chat, inbox, deliveries } = setup({
      conversation: {
        ...conversationRow,
        inbox: { id: "i1", name: "SMS", channel: "sms" },
      },
    });

    await expect(
      deliver({ chat, inbox })({ message_id: "m1", conversation_id: "c1" }),
    ).rejects.toThrow("rate limited");
    expect(deliveries()).toMatchObject([
      { channel: "sms", status: "failed", error: "rate limited" },
    ]);
  });

  it("retries a rate-limited post after the wait it asks for", async () => {
    const { chat, inbox, postMessage, deliveries } = setup();
    postMessage
      .mockRejectedValueOnce(new RateLimitError("slow down", 1))
      .mockRejectedValueOnce(
        Object.assign(new Error("slack 429"), {
          code: "RATE_LIMITED",
          retryAfter: 0,
        }),
      );

    const raw = await deliver({ chat, inbox })({
      message_id: "m1",
      conversation_id: "c1",
    });

    expect(raw?.id).toBe("wamid.out");
    expect(postMessage).toHaveBeenCalledTimes(3);
    expect(deliveries()).toMatchObject([{ status: "sent" }]);

    const long = setup();
    long.postMessage.mockRejectedValue(new RateLimitError("later", 60_000));
    await expect(
      deliver({ chat: long.chat, inbox: long.inbox })({
        message_id: "m1",
        conversation_id: "c1",
      }),
    ).rejects.toThrow("later");
    expect(long.postMessage).toHaveBeenCalledOnce();

    const capped = setup();
    capped.postMessage.mockRejectedValue(new RateLimitError("again"));
    await expect(
      deliver({ chat: capped.chat, inbox: capped.inbox, rateLimitRetries: 1 })({
        message_id: "m1",
        conversation_id: "c1",
      }),
    ).rejects.toThrow("again");
    expect(capped.postMessage).toHaveBeenCalledTimes(2);
  });

  it("skips notes, deleted and orphaned messages", async () => {
    for (const overrides of [
      { message: null },
      { message: { ...messageRow, kind: "note" } },
      { message: { ...messageRow, deleted_at: AT } },
      { conversation: null },
    ]) {
      const { chat, inbox } = setup(overrides);
      expect(
        await deliver({ chat, inbox })({
          message_id: "m1",
          conversation_id: "c1",
        }),
      ).toBeNull();
    }
  });

  it("fails without an adapter", async () => {
    const { chat, inbox } = setup({
      conversation: { ...conversationRow, inbox: null },
    });

    await expect(
      deliver({ chat, inbox })({ message_id: "m1", conversation_id: "c1" }),
    ).rejects.toThrow(/no adapter/);
    const custom = setup();
    await expect(
      deliver({
        chat: custom.chat,
        inbox: custom.inbox,
        adapterFor: () => "teams",
      })({ message_id: "m1", conversation_id: "c1" }),
    ).rejects.toThrow(/no adapter/);
  });
});

describe("whatsappWindowOpen", () => {
  const inboxWith = (rows: unknown[]) =>
    createInbox({
      transport: fakeTransport({ list_inbox_messages: rows }).transport,
    });

  const at = Temporal.Instant.from(AT);

  it("is open within 24 hours of the contact's last message", async () => {
    const rows = [
      messageRow,
      {
        ...messageRow,
        id: "out",
        direction: "outbound",
        created_at: "2026-01-02T00:00:00Z",
      },
    ];

    expect(
      await whatsappWindowOpen(inboxWith(rows), "c1", at.add({ hours: 23 })),
    ).toBe(true);
    expect(
      await whatsappWindowOpen(inboxWith(rows), "c1", at.add({ hours: 25 })),
    ).toBe(false);
    expect(
      await whatsappWindowOpen(
        inboxWith([{ ...messageRow, kind: "note" }]),
        "c1",
        at,
      ),
    ).toBe(false);
    expect(await whatsappWindowOpen(inboxWith([]), "c1")).toBe(false);
  });
});

describe("maintain", () => {
  it("wakes, publishes, replays, purges and sweeps", async () => {
    const { transport, call } = fakeTransport({
      wake_snoozed_conversations: 2,
      publish_due_inbox_messages: 3,
      purge_inbound_events: 5,
    });

    const inbox = createInbox({ transport });

    const handler = {
      process: vi.fn(),
      mirror: vi.fn(),
      drain: vi.fn(async () => ({ processed: 1, failed: 0 })),
      importFiles: vi.fn(),
    };

    const state = { purge: vi.fn(async () => 7) };
    expect(
      await maintain({ inbox, handler, state, keepEvents: "1 day" }),
    ).toEqual({
      woken: 2,
      published: 3,
      purgedEvents: 5,
      replayed: { processed: 1, failed: 0 },
      purgedState: 7,
    });
    expect(
      call.mock.calls.find(([, fn]) => fn === "purge_inbound_events")?.[2],
    ).toMatchObject({ older_than: "1 day" });
    expect(await maintain({ inbox })).toMatchObject({
      replayed: { processed: 0, failed: 0 },
      purgedState: 0,
    });
  });
});
