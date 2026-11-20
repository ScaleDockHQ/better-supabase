import type * as WorkflowWorld from "@workflow/world";
import type { Pool } from "pg";

import { describe, expect, it, vi } from "vitest";

import type {
  VercelDeliveryMetadata,
  VercelQueueSdk,
  VercelRetryDirective,
} from "../../../src/workflow-sdk/world/vercel-queue.ts";

const inner = vi.fn(
  async (_request: Request): Promise<Response> =>
    new Response("{}", { status: 200 }),
);

vi.mock(import("@workflow/world-postgres"), () => ({
  // SAFETY: the World reads only these members of the inner World.
  createWorld: () =>
    ({
      runs: { waitForTerminalStatus: async () => undefined },
      events: { subscribe: () => () => undefined },
      streams: { get: async () => new ReadableStream(), list: async () => [] },
      createQueueHandler: () => inner,
      close: async () => undefined,
    }) as never,
}));

vi.mock(import("@workflow/world"), async (importOriginal) => ({
  ...(await importOriginal<typeof WorkflowWorld>()),
  reenqueueActiveRuns: vi.fn(async () => undefined),
}));

const { createSupabaseWorld } =
  await import("../../../src/workflow-sdk/world/index.ts");

const { timeoutOf } =
  await import("../../../src/workflow-sdk/world/vercel-delivery.ts");

interface Sent {
  readonly topic: string;
  readonly payload: Record<string, unknown>;
  readonly options: Record<string, unknown> | undefined;
}

/**
 * A `QueueClient` whose route runs the handler on a JSON `{ message, metadata
 * }` request and answers the retry directive like Vercel does.
 */
function fakeSdk(overrides: Partial<VercelQueueSdk> = {}) {
  const sent: Sent[] = [];
  const batches: unknown[][] = [];

  const sdk: VercelQueueSdk = {
    send: async (topic, payload, options) => {
      sent.push({
        topic,
        payload: payload as Record<string, unknown>,
        options: options as Record<string, unknown> | undefined,
      });

      return { messageId: "vqs_1" };
    },
    handleCallback: (handler, options) => async (request) => {
      const { message, metadata } = (await request.json()) as {
        message: unknown;
        metadata: VercelDeliveryMetadata;
      };

      try {
        await handler(message, metadata);

        return new Response(null, { status: 200 });
      } catch (error) {
        const directive: VercelRetryDirective | undefined = options?.retry?.(
          error,
          metadata,
        );

        return Response.json(directive ?? {}, { status: 500 });
      }
    },
    ...overrides,
  };

  return { sdk, sent, batches };
}

function fakePool(): { pool: Pool; queries: string[] } {
  const queries: string[] = [];

  const query = vi.fn(async (text: string) => {
    queries.push(text);

    return { rows: [] };
  });

  // SAFETY: the World only calls query and end on its pool.
  return {
    pool: { query, end: async () => undefined } as unknown as Pool,
    queries,
  };
}

function storedMessage(extra: Record<string, unknown> = {}) {
  return {
    queueName: "__wkf_workflow_orders",
    messageId: "msg_1",
    attempt: 1,
    body: Buffer.from(JSON.stringify({ runId: "wrun_1" })).toString("base64"),
    ...extra,
  };
}

function deliver(
  route: (request: Request) => Promise<Response>,
  message: unknown,
  deliveryCount = 1,
): Promise<Response> {
  return route(
    new Request("https://app.test/flow", {
      method: "POST",
      body: JSON.stringify({
        message,
        metadata: { messageId: "vqs_1", deliveryCount },
      }),
    }),
  );
}

describe("timeoutOf", () => {
  it("reads the wait a flow response asks for", () => {
    expect(timeoutOf('{"timeoutSeconds":5}')).toBe(5);
    expect(timeoutOf('{"timeoutSeconds":0}')).toBe(0);
    expect(timeoutOf('{"timeoutSeconds":-1}')).toBeUndefined();
    expect(timeoutOf("{}")).toBeUndefined();
    expect(timeoutOf("not json")).toBeUndefined();
  });
});

describe('delivery: "vercel-queue"', () => {
  it("sends a message to its topic without touching the queue tables", async () => {
    const { sdk, sent } = fakeSdk();
    const { pool, queries } = fakePool();

    const world = createSupabaseWorld({
      pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    const result = await world.queue(
      "__wkf_workflow_orders",
      { runId: "wrun_1" },
      { idempotencyKey: "run:wrun_1" },
    );

    expect(result.messageId).toMatch(/^msg_/);
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      topic: "__wkf_workflow_orders",
      payload: { queueName: "__wkf_workflow_orders", attempt: 1 },
      options: { delaySeconds: 0, idempotencyKey: "run:wrun_1" },
    });
    expect(sent[0]!.options).not.toHaveProperty("retentionSeconds");
    expect(queries.some((text) => text.includes("enqueue_job"))).toBe(false);
    await world.close();
  });

  it("chains a delay past 23 hours through hops and keeps the message for it", async () => {
    const { sdk, sent } = fakeSdk();

    const world = createSupabaseWorld({
      pool: fakePool().pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    await world.queue(
      "__wkf_workflow_orders",
      { runId: "wrun_1" },
      { delaySeconds: 25 * 3600, idempotencyKey: "wait" },
    );

    expect(sent[0]!.payload["remainingDelay"]).toBe(2 * 3600);
    expect(sent[0]!.options).toMatchObject({
      delaySeconds: 23 * 3600,
      retentionSeconds: 24 * 3600,
      idempotencyKey: "wait:hop:7200",
    });
    await world.close();
  });

  it("sends a hop on without running the flow, and runs the last one", async () => {
    const { sdk, sent } = fakeSdk();

    const world = createSupabaseWorld({
      pool: fakePool().pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    inner.mockClear();

    const route = world.createQueueHandler("__wkf_workflow_", vi.fn() as never);

    const hop = await deliver(
      route,
      storedMessage({ remainingDelay: 30 * 3600 }),
    );

    expect(hop.status).toBe(200);
    expect(inner).not.toHaveBeenCalled();
    expect(sent[0]!.options).toMatchObject({ delaySeconds: 23 * 3600 });
    expect(sent[0]!.payload["remainingDelay"]).toBe(7 * 3600);

    const last = await deliver(route, storedMessage());
    expect(last.status).toBe(200);
    expect(inner).toHaveBeenCalledOnce();
    await world.close();
  });

  it("gives the flow route the delivery count and attempt, then clears the wake-up", async () => {
    const { sdk } = fakeSdk();
    const { pool, queries } = fakePool();

    const world = createSupabaseWorld({
      pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    inner.mockClear();

    const route = world.createQueueHandler("__wkf_workflow_", vi.fn() as never);

    await deliver(route, storedMessage({ attempt: 2 }), 3);

    const request = inner.mock.calls[0]![0];
    expect(request.headers.get("x-vqs-message-delivery-count")).toBe("3");
    expect(request.headers.get("x-vqs-message-attempt")).toBe("4");
    expect(request.headers.get("x-vqs-queue-name")).toBe(
      "__wkf_workflow_orders",
    );
    expect(await request.text()).toBe('{"runId":"wrun_1"}');
    expect(queries.some((text) => text.includes("wake_pending = false"))).toBe(
      true,
    );
    await world.close();
  });

  it("sends the message on when the flow asks to wait, and keeps the wake-up", async () => {
    const { sdk, sent } = fakeSdk();
    const { pool, queries } = fakePool();

    const world = createSupabaseWorld({
      pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    inner.mockResolvedValueOnce(
      new Response('{"timeoutSeconds":45}', { status: 200 }),
    );

    const route = world.createQueueHandler("__wkf_workflow_", vi.fn() as never);

    const response = await deliver(route, storedMessage());
    expect(response.status).toBe(200);
    expect(sent).toHaveLength(1);
    expect(sent[0]!.payload["attempt"]).toBe(2);
    expect(sent[0]!.options).toMatchObject({ delaySeconds: 45 });
    expect(queries.some((text) => text.includes("wake_pending = false"))).toBe(
      false,
    );
    await world.close();
  });

  it("backs off a failed delivery within Vercel's range and dead-letters the last one", async () => {
    const { sdk } = fakeSdk();
    const onDeadLetter = vi.fn();

    const world = createSupabaseWorld({
      pool: fakePool().pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
      onDeadLetter,
      logger: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    });

    const route = world.createQueueHandler("__wkf_workflow_", vi.fn() as never);

    inner.mockResolvedValueOnce(new Response("boom", { status: 500 }));

    const first = await deliver(route, storedMessage(), 1);
    expect(first.status).toBe(500);
    expect(await first.json()).toEqual({ afterSeconds: 5 });

    inner.mockRejectedValueOnce(new Error("function timed out"));

    const later = await deliver(route, storedMessage(), 40);
    expect(await later.json()).toEqual({ afterSeconds: 900 });
    expect(onDeadLetter).not.toHaveBeenCalled();

    inner.mockResolvedValueOnce(new Response("boom", { status: 500 }));

    const last = await deliver(route, storedMessage(), 73);
    expect(await last.json()).toEqual({ acknowledge: true });

    await vi.waitFor(() => {
      expect(onDeadLetter).toHaveBeenCalledOnce();
    });
    expect(onDeadLetter.mock.calls[0]![0]).toMatchObject({
      queueName: "__wkf_workflow_orders",
      messageId: "msg_1",
      runId: "wrun_1",
      attempts: 73,
      error: "Flow route answered 500: boom",
    });
    await world.close();
  });

  it("drops a message that is not a workflow message instead of retrying it", async () => {
    const { sdk } = fakeSdk();

    const world = createSupabaseWorld({
      pool: fakePool().pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
      logger: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    });

    const route = world.createQueueHandler("__wkf_workflow_", vi.fn() as never);

    expect((await deliver(route, { nope: true })).status).toBe(200);
    await world.close();
  });

  it("sends a batch with sendBatch and reports each failure as retryable", async () => {
    const calls: { topic: string; messages: unknown[] }[] = [];

    const { sdk } = fakeSdk({
      sendBatch: async (topic, messages) => {
        calls.push({ topic, messages: [...messages] });

        return [
          { status: "sent", messageId: "a" },
          { status: "failed", statusCode: 503, error: "busy" },
          { status: "deferred", messageId: null },
        ];
      },
    });

    const world = createSupabaseWorld({
      pool: fakePool().pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    const results = await world.queueBatch!("__wkf_step_orders", [
      { message: { a: 1 } as never },
      { message: { a: 2 } as never },
      { message: { a: 3 } as never, opts: { delaySeconds: 5 } },
    ]);

    expect(calls).toHaveLength(1);
    expect(calls[0]!.topic).toBe("__wkf_step_orders");
    expect(results[0]).toEqual({ messageId: expect.stringMatching(/^msg_/) });
    expect(results[1]).toEqual({
      messageId: null,
      error: "busy",
      retryable: true,
    });
    expect(results[2]).toEqual({ messageId: expect.stringMatching(/^msg_/) });
    await world.close();
  });

  it("sends a batch one message at a time when the client has no sendBatch", async () => {
    const { sdk, sent } = fakeSdk();

    const world = createSupabaseWorld({
      pool: fakePool().pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    const results = await world.queueBatch!("__wkf_step_orders", [
      { message: { a: 1 } as never },
      { message: { a: 2 } as never },
    ]);

    expect(sent).toHaveLength(2);
    expect(results.every((result) => result.messageId !== null)).toBe(true);
    await world.close();
  });

  it("reports a whole batch as retryable when the send fails", async () => {
    const { sdk } = fakeSdk({
      send: async () => {
        throw new Error("unauthorized");
      },
    });

    const world = createSupabaseWorld({
      pool: fakePool().pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    const results = await world.queueBatch!("__wkf_step_orders", [
      { message: { a: 1 } as never },
    ]);

    expect(results).toEqual([
      { messageId: null, error: "unauthorized", retryable: true },
    ]);
    await expect(
      world.queue("__wkf_step_orders", { a: 1 } as never),
    ).rejects.toThrow("unauthorized");
    await world.close();
  });

  it("does not poll the queue table", async () => {
    const { sdk } = fakeSdk();
    const { pool, queries } = fakePool();

    const world = createSupabaseWorld({
      pool,
      delivery: "vercel-queue",
      vercelQueue: sdk,
    });

    await world.queue("__wkf_workflow_orders", { runId: "wrun_1" });
    await world.close();
    expect(queries.some((text) => text.includes("claim_jobs"))).toBe(false);
  });
});
