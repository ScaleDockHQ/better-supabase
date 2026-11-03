import { createMockState } from "@chat-adapter/tests";
import { describe, expect, it, vi } from "vitest";

import type { ChatLike } from "../../src/chat-sdk/index.ts";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import { chatWebhookPipeline } from "../../src/chat-sdk/index.ts";
import { fakeTransport } from "../blocks/inbox/fixtures.ts";

type Handle = ChatLike["webhooks"][string];

function chatOf(prefix: string, handle: Handle): ChatLike {
  const state = Object.assign(createMockState(), { keyPrefix: prefix });

  return {
    webhooks: { slack: handle },
    getAdapter: () => undefined,
    getState: () => state,
  };
}

const request = (body = '{"a":1}') =>
  new Request("https://app.test/hooks/slack", { method: "POST", body });

function setup(options: { process?: Handle; receive?: Handle } = {}) {
  const stored: unknown[] = [];

  const sink = {
    store: vi.fn(async (event: unknown) => {
      stored.push(event);

      return { ok: true, data: { id: "e1", duplicate: false } };
    }),
  };

  const receiveHandle = vi.fn<Handle>(
    options.receive ?? (async () => new Response("ok")),
  );

  const processHandle = vi.fn<Handle>(
    options.process ?? (async () => new Response("ok")),
  );

  const inbox = createInbox({
    transport: fakeTransport({ set_inbound_event_status: true }).transport,
  });

  return {
    stored,
    sink,
    receiveHandle,
    processHandle,
    pipeline: (extra: Record<string, unknown> = {}) =>
      chatWebhookPipeline({
        chat: chatOf("chat-sdk", processHandle),
        receiveChat: chatOf("chat-sdk:receive", receiveHandle),
        adapter: "slack",
        inbox,
        inboxes: { slack: "i1" },
        sink,
        ...extra,
      }),
  };
}

describe("chatWebhookPipeline", () => {
  it("stores what the receiving adapter accepts, then replays it once per attempt", async () => {
    const { pipeline, stored, receiveHandle, processHandle } = setup();
    const { receive, process } = pipeline();

    expect((await receive(request())).status).toBe(200);
    expect(receiveHandle).toHaveBeenCalledOnce();
    expect(stored).toHaveLength(1);

    const [first] = stored as { payload: { body: string } }[];

    expect(first?.payload.body).toBe('{"a":1}');

    await process({
      id: "e1",
      adapter: "slack",
      headers: {},
      body: '{"a":1}',
      attempt: 3,
    });

    const options = processHandle.mock.calls[0]?.[1] as Record<string, unknown>;

    expect(options["deduplicate"]).toBe(false);
    expect(options["propagateHandlerErrors"]).toBe(true);
    expect(receiveHandle.mock.calls[0]?.[1]).not.toHaveProperty(
      "propagateHandlerErrors",
    );
  });

  it("stores nothing when the receiving adapter rejects the request", async () => {
    const { pipeline, stored } = setup({
      receive: async () => new Response("bad signature", { status: 401 }),
    });

    expect((await pipeline().receive(request())).status).toBe(401);
    expect(stored).toHaveLength(0);
  });

  it("awaits the handler tasks and rethrows a failure so the job retries", async () => {
    const { pipeline } = setup({
      process: async (_request, options) => {
        options?.waitUntil?.(Promise.reject(new Error("handler crashed")));

        return new Response("ok");
      },
    });

    const failing = { id: "e1", adapter: "slack", headers: {}, body: "{}" };

    await expect(pipeline().process(failing)).rejects.toThrow(
      /handler crashed|answered/,
    );
  });

  it("hands a retry delay back instead of throwing when retry decides", async () => {
    const { pipeline } = setup({
      process: async () => new Response("later", { status: 500 }),
    });

    const result = await pipeline({
      retry: () => ({ retryIn: "2 minutes" }),
    }).process({ id: "e1", adapter: "slack", headers: {}, body: "{}" });

    expect(result).toEqual({ retryIn: "2 minutes" });
  });

  it("throws a TypeError when both Chat instances share a state prefix", () => {
    const handle: Handle = async () => new Response("ok");
    const sink = { store: vi.fn() };
    const chat = chatOf("chat-sdk", handle);

    expect(() =>
      chatWebhookPipeline({
        chat,
        receiveChat: chatOf("chat-sdk", handle),
        adapter: "slack",
        sink,
        inbox: createInbox({ transport: fakeTransport({}).transport }),
        inboxes: {},
      }),
    ).toThrow(TypeError);
    expect(() =>
      chatWebhookPipeline({
        chat,
        receiveChat: chat,
        adapter: "slack",
        sink,
        inbox: createInbox({ transport: fakeTransport({}).transport }),
        inboxes: {},
      }),
    ).toThrow(/state prefix/);
  });
});
