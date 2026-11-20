import { describe, expect, it, vi } from "vitest";

import type { Inbox } from "../../src/blocks/inbox/inbox.ts";
import type {
  Conversation,
  StoredInboundEvent,
} from "../../src/blocks/inbox/types.ts";
import type { EveDispatchOptions } from "../../src/eve/schedules.ts";
import type { EveSessionReply } from "../../src/eve/sync.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  inboxConnectionWebhook,
  inboxHandoff,
  inboxPrincipal,
  inboxReplies,
  inboxRunAs,
} from "../../src/eve/index.ts";

const ORG = "22222222-2222-4222-8222-222222222222";

const conversation = (botMode: "bot" | "human" = "bot"): Conversation =>
  // SAFETY: the tests read only these fields.
  ({
    id: "conv_1",
    tenant: ORG,
    contactId: "contact_1",
    subject: "Where is my order",
    botMode,
  }) as unknown as Conversation;

const event = (adapter = "whatsapp"): StoredInboundEvent =>
  // SAFETY: the handoff reads only these fields.
  ({
    id: "ev_1",
    adapter,
    inboxId: "inbox_1",
    body: "{}",
  }) as unknown as StoredInboundEvent;

function fakeInbox(
  options: {
    readonly events?: StoredInboundEvent[];
    readonly conversation?: Conversation;
    readonly duplicate?: boolean;
    readonly drafts?: unknown[];
  } = {},
) {
  const calls: { fn: string; args: unknown }[] = [];

  const rec =
    <T>(fn: string, value: T) =>
    (args?: unknown) => {
      calls.push({ fn, args });

      return AsyncResult.ok(value);
    };

  const inbox = {
    inbound: {
      pending: rec("pending", options.events ?? []),
      setStatus: rec("setStatus", true),
      store: rec("store", { id: "ev_1", duplicate: false }),
      record: rec("record", {
        conversationId: "conv_1",
        messageId: "msg_1",
        contactId: "contact_1",
        tenant: ORG,
        created: true,
        duplicate: options.duplicate ?? false,
      }),
    },
    conversations: {
      getConversation: (id: string) => {
        calls.push({ fn: "getConversation", args: id });

        return id === "conv_1"
          ? AsyncResult.ok(options.conversation ?? conversation())
          : AsyncResult.err(dbError("not_found", "no conversation"));
      },
    },
    messages: { send: rec("send", {}) },
    drafts: {
      list: rec("drafts.list", options.drafts ?? []),
      suggest: rec("drafts.suggest", {}),
    },
  };

  // SAFETY: the fake implements the calls these helpers make.
  return { inbox: inbox as unknown as Inbox, calls };
}

const dispatch = () => {
  const send = vi.fn(() => Promise.resolve());
  const to = vi.fn(() => ({ send }));

  const args: EveDispatchOptions = {
    // SAFETY: the test's `to` accepts any channel and target.
    to,
    appAuth: {
      authenticator: "app",
      principalType: "runtime",
      principalId: "eve:app",
      attributes: {},
    },
  };

  return { args, send, to };
};

describe("inboxConnectionWebhook", () => {
  const post = (path: string) =>
    new Request(`https://app.test${path}`, { method: "POST", body: '{"x":1}' });

  it("answers 404 for an unknown connection", async () => {
    const { inbox } = fakeInbox();
    const handle = inboxConnectionWebhook({ inbox, connection: () => {} });

    expect((await handle(post("/hooks/nope"))).status).toBe(404);
  });

  it("refuses a connection that has nothing to verify with", async () => {
    const { inbox, calls } = fakeInbox();

    const handle = inboxConnectionWebhook({
      inbox,
      connection: () => ({ adapter: "whatsapp", tenant: ORG }),
    });

    expect((await handle(post("/hooks/c1"))).status).toBe(500);
    expect(calls).toEqual([]);
  });

  it("verifies with the connection's own check before it stores", async () => {
    const { inbox, calls } = fakeInbox();
    const seen: string[] = [];

    const handle = inboxConnectionWebhook({
      inbox,
      connection: (id) => {
        seen.push(id);

        return {
          adapter: "whatsapp",
          tenant: ORG,
          inboxId: "inbox_1",
          verify: (request) => request.headers.get("x-sig") === id,
          externalId: () => "wamid.1",
        };
      },
    });

    const bad = await handle(post("/hooks/c1"));

    expect(bad.status).toBe(401);
    expect(calls).toEqual([]);

    const good = await handle(
      new Request("https://app.test/hooks/c1", {
        method: "POST",
        body: "{}",
        headers: { "x-sig": "c1" },
      }),
    );

    expect(good.status).toBe(200);
    expect(seen).toEqual(["c1", "c1"]);
    expect(calls[0]).toMatchObject({
      fn: "store",
      args: {
        adapter: "whatsapp",
        tenant: ORG,
        inboxId: "inbox_1",
        externalId: "wamid.1",
      },
    });
  });
});

describe("inboxHandoff", () => {
  const parsers = {
    whatsapp: () => ({
      threadId: "wa:1",
      contact: { externalId: "1" },
      text: "hello",
      externalId: "wamid.1",
    }),
  };

  it("stores the message and hands a bot conversation to eve", async () => {
    const { inbox, calls } = fakeInbox({ events: [event()] });
    const { args, send, to } = dispatch();
    const channel = {};

    const result = await inboxHandoff({ inbox, parsers, channel })(args);

    expect(result).toEqual({ processed: 1, ignored: 0, failed: 0 });
    expect(to).toHaveBeenCalledWith(channel, { conversationId: "conv_1" });
    expect(send).toHaveBeenCalledWith("hello", {
      auth: inboxPrincipal(conversation()),
      idempotencyKey: "msg_1",
      title: "Where is my order",
    });
    expect(calls.map((call) => call.fn)).toContain("record");
    expect(calls.at(-1)).toMatchObject({
      fn: "setStatus",
      args: { status: "processed" },
    });
  });

  it("keeps a human conversation and a duplicate away from eve", async () => {
    const human = fakeInbox({
      events: [event()],
      conversation: conversation("human"),
    });

    const first = dispatch();

    await inboxHandoff({ inbox: human.inbox, parsers, channel: {} })(
      first.args,
    );

    const dup = fakeInbox({ events: [event()], duplicate: true });
    const second = dispatch();

    await inboxHandoff({ inbox: dup.inbox, parsers, channel: {} })(second.args);

    expect(first.send).not.toHaveBeenCalled();
    expect(second.send).not.toHaveBeenCalled();
  });

  it("ignores events without a parser or a message and fails a throw", async () => {
    const { inbox, calls } = fakeInbox({
      events: [event("unknown"), event("status"), event()],
    });

    const { args } = dispatch();

    const result = await inboxHandoff({
      inbox,
      parsers: {
        status: () => {},
        whatsapp: () => {
          throw new Error("bad payload");
        },
      },
      channel: {},
    })(args);

    expect(result).toEqual({ processed: 0, ignored: 2, failed: 1 });
    expect(calls.findLast((call) => call.fn === "setStatus")).toMatchObject({
      args: { status: "failed", error: "bad payload" },
    });
  });
});

describe("inboxRunAs", () => {
  it("runs an inbox principal as the service user in its tenant", () => {
    const runAs = inboxRunAs({ userId: "svc" });

    expect(runAs(inboxPrincipal(conversation()))).toEqual({
      userId: "svc",
      tenant: ORG,
    });
    expect(
      runAs({
        authenticator: "supabase",
        principalType: "user",
        principalId: "u",
        attributes: { tenantId: ORG },
      }),
    ).toBeUndefined();
    expect(runAs(null)).toBeUndefined();
    expect(
      inboxRunAs({ userId: () => {} })(inboxPrincipal(conversation())),
    ).toBeUndefined();
  });
});

describe("inboxReplies", () => {
  const reply = (principalId = "conv_1"): EveSessionReply => ({
    sessionId: "sess_1",
    chatId: "chat_1",
    turnId: "t1",
    key: "t1:p",
    text: "It ships today",
    target: { organizationId: ORG, ownerId: "svc" },
    principal: { id: principalId, type: "contact" },
  });

  it("sends the reply as a bot message keyed by the turn", async () => {
    const { inbox, calls } = fakeInbox();

    await inboxReplies({ inbox })(reply());

    expect(calls.at(-1)).toEqual({
      fn: "send",
      args: {
        conversationId: "conv_1",
        input: {
          body: "It ships today",
          authorType: "bot",
          externalId: "eve:t1:p",
        },
      },
    });
  });

  it("stores an ai draft once in draft mode", async () => {
    const first = fakeInbox();

    await inboxReplies({ inbox: first.inbox, mode: "draft" })(reply());

    expect(first.calls.at(-1)).toMatchObject({
      fn: "drafts.suggest",
      args: {
        conversationId: "conv_1",
        input: { body: "It ships today" },
        metadata: { eveReplyKey: "t1:p" },
      },
    });

    const again = fakeInbox({
      drafts: [{ metadata: { eveReplyKey: "t1:p" } }],
    });

    await inboxReplies({ inbox: again.inbox, mode: () => "draft" })(reply());

    expect(again.calls.map((call) => call.fn)).not.toContain("drafts.suggest");
  });

  it("leaves other principals and tenants alone", async () => {
    const { inbox, calls } = fakeInbox();

    await inboxReplies({ inbox })({
      ...reply(),
      principal: { id: "u", type: "user" },
    });
    await inboxReplies({ inbox })(reply("contact_1"));
    await inboxReplies({ inbox })({
      ...reply(),
      target: { organizationId: "other", ownerId: "svc" },
    });

    expect(calls.map((call) => call.fn)).not.toContain("send");
  });
});
