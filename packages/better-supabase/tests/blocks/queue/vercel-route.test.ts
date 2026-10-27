import type { QueueClient } from "@vercel/queue";

import * as v from "valibot";
import { describe, expect, it, vi } from "vitest";

import type {
  VercelQueueCallbackClient,
  VercelQueueNodeCallbackClient,
  VercelRetryDirective,
} from "../../../src/blocks/queue/index.ts";

import {
  createQueue,
  vercelQueueNodeRoute,
  vercelQueueProvider,
  vercelQueueRoute,
} from "../../../src/blocks/queue/index.ts";

// The real client must fit the structural types.
export const fits = (client: QueueClient): VercelQueueCallbackClient => client;

export const nodeFits = (client: QueueClient): VercelQueueNodeCallbackClient =>
  client;

interface Delivery {
  readonly topicName: string;
  readonly body: unknown;
  readonly deliveryCount: number;
}

/** A QueueClient whose route reads one delivery from the request's JSON. */
function callbackClient(): VercelQueueCallbackClient & {
  readonly directives: (VercelRetryDirective | undefined)[];
  readonly options: { visibilityTimeoutSeconds: number | undefined }[];
} {
  const directives: (VercelRetryDirective | undefined)[] = [];
  const options: { visibilityTimeoutSeconds: number | undefined }[] = [];

  return {
    directives,
    options,
    handleCallback(handler, handlerOptions) {
      options.push({
        visibilityTimeoutSeconds: handlerOptions?.visibilityTimeoutSeconds,
      });

      return async (request) => {
        // SAFETY: the tests post a Delivery.
        const delivery = (await request.json()) as Delivery;

        const metadata = {
          messageId: "m1",
          deliveryCount: delivery.deliveryCount,
          createdAt: new Date("2026-10-27T10:00:00Z"),
          expiresAt: new Date("2026-10-28T10:00:00Z"),
          topicName: delivery.topicName,
        };

        try {
          await handler(delivery.body, metadata);

          return Response.json({ status: "success" });
        } catch (error) {
          directives.push(handlerOptions?.retry?.(error, metadata));

          return Response.json({ status: "retry" });
        }
      };
    },
  };
}

const post = (delivery: Delivery): Request =>
  new Request("http://localhost/api/queues/emails", {
    method: "POST",
    body: JSON.stringify(delivery),
  });

const jobs = createQueue({
  backend: vercelQueueProvider({
    send: () => Promise.resolve({ messageId: null }),
  }),
  queues: { emails: v.object({ to: v.pipe(v.string(), v.email()) }) },
});

describe("vercelQueueRoute", () => {
  it("runs the queue's handler with the parsed payload and the delivery count", async () => {
    const client = callbackClient();

    const handler =
      vi.fn<(payload: { to: string }, attempts: number) => void>();

    const route = vercelQueueRoute(jobs, {
      client,
      handlers: {
        emails: (payload, job) => {
          handler(payload, job.attempts);
        },
      },
    });

    const response = await route(
      post({
        topicName: "emails",
        body: { payload: { to: "a@example.com" }, max_attempts: 3 },
        deliveryCount: 2,
      }),
    );

    expect(await response.json()).toEqual({ status: "success" });
    expect(handler).toHaveBeenCalledWith({ to: "a@example.com" }, 2);
    expect(client.options).toEqual([{ visibilityTimeoutSeconds: 300 }]);
  });

  it("retries a failed delivery and acknowledges the last attempt", async () => {
    const client = callbackClient();
    const onError = vi.fn();

    const route = vercelQueueRoute(jobs, {
      client,
      retryAfter: (attempt) => attempt * 10,
      onError,
      handlers: {
        emails: () => ({ ok: false, error: new Error("smtp down") }),
      },
    });

    for (const deliveryCount of [1, 2]) {
      await route(
        post({
          topicName: "emails",
          body: { payload: { to: "a@example.com" }, max_attempts: 2 },
          deliveryCount,
        }),
      );
    }

    expect(client.directives).toEqual([
      { afterSeconds: 10 },
      { acknowledge: true },
    ]);
    expect(onError.mock.calls.map(([, delivery]) => delivery)).toEqual([
      { queue: "emails", messageId: "m1", attempt: 1, dead: false },
      { queue: "emails", messageId: "m1", attempt: 2, dead: true },
    ]);
  });

  it("rejects a payload its schema refuses, and a topic without a handler", async () => {
    const client = callbackClient();
    const ran = vi.fn();

    const route = vercelQueueRoute(jobs, { client, handlers: { emails: ran } });

    await route(
      post({
        topicName: "emails",
        body: { payload: { to: "nope" }, max_attempts: 5 },
        deliveryCount: 1,
      }),
    );
    await route(post({ topicName: "other", body: {}, deliveryCount: 1 }));

    expect(ran).not.toHaveBeenCalled();
    expect(client.directives).toEqual([
      { afterSeconds: 30 },
      { afterSeconds: 30 },
    ]);
  });

  it("serves (req, res) frameworks through handleNodeCallback", async () => {
    const handler = vi.fn();

    const route = vercelQueueNodeRoute(jobs, {
      client: {
        handleNodeCallback: (consume) => async (request, response) => {
          await consume(request.body, {
            messageId: "m1",
            deliveryCount: 1,
            createdAt: new Date(),
            expiresAt: new Date(),
            topicName: "emails",
          });
          response.end();
        },
      },
      handlers: { emails: handler },
    });

    const end = vi.fn();

    await route(
      {
        headers: {},
        body: { payload: { to: "a@example.com" }, max_attempts: 5 },
      },
      { status: () => ({ json: vi.fn(), end }), end },
    );

    expect(handler).toHaveBeenCalledOnce();
    expect(end).toHaveBeenCalledOnce();
  });
});
