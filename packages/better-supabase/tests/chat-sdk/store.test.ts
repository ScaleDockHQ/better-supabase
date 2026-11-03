import {
  createMockAdapter,
  createMockState,
  createTestMessage,
} from "@chat-adapter/tests";
import { describe, expect, it, vi } from "vitest";

import type { InboxMessage } from "../../src/blocks/inbox/types.ts";
import type {
  ChatInboundStore,
  ChatLike,
  ChatWebhookEvent,
} from "../../src/chat-sdk/index.ts";

import {
  capabilitiesOf,
  chatEventOf,
  deliver,
  inboundHandler,
  maintain,
  webhook,
  whatsappWindowOpen,
} from "../../src/chat-sdk/index.ts";
import { AT } from "../blocks/inbox/fixtures.ts";

const NOW = Temporal.Instant.from(AT);

function memoryStore(overrides: Partial<ChatInboundStore> = {}) {
  const calls: { method: string; input: unknown }[] = [];
  const log = (method: string, input: unknown) => calls.push({ method, input });

  const message = { id: "m2", body: "hello", format: "text", attachments: [] };

  const store: ChatInboundStore = {
    apiVersion: 1,
    recordInbound: async (input) => {
      log("recordInbound", input);

      return {
        conversationId: "c1",
        messageId: "m1",
        duplicate: false,
      } as never;
    },
    recordOutbound: async (input) => {
      log("recordOutbound", input);
    },
    recordDeliveryAttempt: async (input) => {
      log("recordDeliveryAttempt", input);
    },
    updateDeliveryStatus: async (input) => {
      log("updateDeliveryStatus", input);

      return 1;
    },
    lastInboundAt: async () => NOW,
    outbound: async () => ({
      message: message as unknown as InboxMessage,
      conversation: {
        id: "c1",
        threadId: "slack:C1:1",
        inbox: { channel: "slack" },
      } as never,
    }),
    ...overrides,
  };

  return { store, calls };
}

function chatOf(adapters: Record<string, unknown> = {}, webhooks = {}) {
  const state = createMockState();

  const chat: ChatLike = {
    webhooks,
    getAdapter: (name) => adapters[name] as never,
    getState: () => state,
  };

  return { chat, state };
}

describe("ChatInboundStore", () => {
  it("records a channel message through an in-memory store", async () => {
    const { store, calls } = memoryStore();
    const { chat } = chatOf();

    const handler = inboundHandler({
      chat,
      inbox: store,
      inboxes: { slack: "i1" },
    });

    const result = await handler.mirror(
      { id: "slack:C1:1", adapter: { name: "slack" } },
      createTestMessage("1.0", "hi there"),
    );

    expect(result).toMatchObject({ conversationId: "c1" });
    expect(calls[0]).toMatchObject({
      method: "recordInbound",
      input: { inboxId: "i1", threadId: "slack:C1:1" },
    });
  });

  it("delivers a reply, then records a failed attempt that a retry clears", async () => {
    const postMessage = vi
      .fn()
      .mockRejectedValueOnce(new Error("slack down"))
      .mockResolvedValue({ id: "p1", threadId: "slack:C1:1", raw: {} });

    const adapter = createMockAdapter("slack", { postMessage });
    const { chat } = chatOf({ slack: adapter });
    const { store, calls } = memoryStore();
    const send = deliver({ chat, inbox: store });
    const job = { message_id: "m2", conversation_id: "c1" };

    await expect(send(job)).rejects.toThrow("slack down");
    expect(calls.at(-1)).toMatchObject({
      method: "recordDeliveryAttempt",
      input: { messageId: "m2", status: "failed", error: "slack down" },
    });

    expect(await send(job)).toMatchObject({ id: "p1" });
    expect(calls.at(-1)).toMatchObject({
      method: "recordOutbound",
      input: { messageId: "m2", channel: "slack", externalId: "p1" },
    });
  });

  it("posts a reply's attachments as files through download", async () => {
    const postMessage = vi.fn(async () => ({
      id: "p",
      threadId: "t",
      raw: {},
    }));

    const { chat } = chatOf({
      slack: createMockAdapter("slack", { postMessage }),
    });

    const { store } = memoryStore({
      outbound: async () => ({
        message: {
          id: "m2",
          body: "see",
          format: "markdown",
          attachments: [{ id: "f1", name: "a.pdf", status: "clean" }],
        } as never,
        conversation: {
          id: "c1",
          threadId: "slack:C1:1",
          inbox: { channel: "slack" },
        } as never,
      }),
    });

    const data = new ArrayBuffer(2);

    await deliver({
      chat,
      inbox: store,
      download: async (file) => ({ data, filename: file.name }),
    })({ message_id: "m2", conversation_id: "c1" });

    expect(postMessage).toHaveBeenCalledWith("slack:C1:1", {
      markdown: "see",
      files: [{ data, filename: "a.pdf" }],
    });
  });

  it("applies whatsapp delivery statuses and checks the reply window", async () => {
    const { store, calls } = memoryStore();

    const body = JSON.stringify({
      object: "whatsapp_business_account",
      entry: [
        {
          changes: [
            { value: { statuses: [{ id: "w1", status: "delivered" }] } },
          ],
        },
      ],
    });

    await inboundHandler({
      chat: chatOf().chat,
      inbox: store,
      inboxes: {},
    }).process({
      id: "e1",
      adapter: "whatsapp",
      headers: { "content-type": "application/json" },
      body,
    });

    expect(calls[0]).toMatchObject({
      method: "updateDeliveryStatus",
      input: { channel: "whatsapp", externalId: "w1", status: "delivered" },
    });
    expect(await whatsappWindowOpen(store, "c1", NOW.add({ hours: 23 }))).toBe(
      true,
    );
    expect(await whatsappWindowOpen(store, "c1", NOW.add({ hours: 25 }))).toBe(
      false,
    );
  });

  it("runs the store's own maintenance and the rest", async () => {
    const { store } = memoryStore({
      maintain: async () => ({ woken: 2, published: 1, purgedEvents: 3 }),
    });

    expect(await maintain({ inbox: store })).toMatchObject({
      woken: 2,
      published: 1,
      purgedEvents: 3,
      posted: 0,
    });
  });
});

describe("webhook sink", () => {
  it("stores the raw request in the sink and replays it with process", async () => {
    const stored: ChatWebhookEvent[] = [];

    const sink = {
      store: async (event: ChatWebhookEvent) => {
        stored.push(event);

        return { ok: true, data: { id: 7 } };
      },
    };

    const handle = webhook({
      sink,
      adapter: "slack",
      externalId: () => "evt1",
    });

    const response = await handle(
      new Request("https://app.test/hooks/slack", {
        method: "POST",
        headers: { "content-type": "application/json", cookie: "a=b" },
        body: '{"x":1}',
      }),
    );

    expect(response.status).toBe(200);
    expect(stored[0]).toMatchObject({
      id: "evt1",
      payload: { adapter: "slack", body: '{"x":1}' },
    });
    expect(JSON.stringify(stored[0])).not.toContain("cookie");

    const handler = vi.fn(async () => new Response("ok"));
    const { store } = memoryStore();

    await inboundHandler({
      chat: chatOf({}, { slack: handler }).chat,
      inbox: store,
      inboxes: {},
    }).process(
      chatEventOf({ id: 7, payload: stored[0]?.payload }) ?? {
        id: "x",
        adapter: "",
        headers: {},
        body: "",
      },
    );

    expect(handler).toHaveBeenCalledOnce();
  });

  it("answers 503 when the sink fails, and rejects without a destination", async () => {
    const request = () =>
      new Request("https://app.test/h", { method: "POST", body: "{}" });

    for (const sink of [
      { store: async () => ({ ok: false }) },
      {
        store: async () => {
          throw new Error("down");
        },
      },
    ]) {
      const handle = webhook({ sink, adapter: "slack" });
      expect((await handle(request())).status).toBe(503);
    }

    expect(() => webhook({ adapter: "slack" })).toThrow(/inbox.*sink/);
    expect(chatEventOf({ id: 1, payload: { nope: true } })).toBeNull();
  });
});

describe("capabilitiesOf", () => {
  const load = async () => ({
    getCatalogEntry: (slug: string) =>
      slug === "slack"
        ? {
            slug,
            name: "Slack",
            type: "platform",
            group: "official",
            packageName: "@chat-adapter/slack",
            features: {
              cards: { status: "yes", label: "Block Kit" },
              polls: "no",
            },
          }
        : undefined,
  });

  it("reads the catalog entry", async () => {
    const result = await capabilitiesOf("slack", { load }).orThrow();
    expect(result.features["cards"]).toEqual({
      status: "yes",
      label: "Block Kit",
    });
    expect(result.features["polls"]).toEqual({ status: "no" });
  });

  it("reports an unknown adapter and a missing catalog", async () => {
    const unknown = await capabilitiesOf("nope", { load });
    expect(unknown.ok).toBe(false);

    const missing = await capabilitiesOf("slack", { load: async () => ({}) });

    expect(missing.ok).toBe(false);
  });
});
