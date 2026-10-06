import { describe, expect, it } from "vitest";

import type {
  WebhookRequest,
  WebhookResponse,
  WebhookTransport,
  WebhooksOptions,
} from "../../../src/blocks/webhooks/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createWebhooks,
  sqlSecretStore,
  verifyWebhook,
  WebhookPolicyError,
} from "../../../src/blocks/webhooks/index.ts";
import { EventHub } from "../../../src/core/events.ts";
import { testWebhookSecretStore } from "../../../src/testing/index.ts";

const SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";

interface Call {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: "del-1",
    endpoint_id: "dest-1",
    url: "https://hooks.example.com/in",
    type: "invoice.paid",
    payload: { id: 7 },
    attempt: 1,
    tenant: "org-1",
    event_id: "evt-1",
    run_id: null,
    created_at: "2026-10-03T10:00:00Z",
    ...overrides,
  };
}

/** Serves `claimed` once, then nothing; answers the rest from `results`. */
function fakeBlock(
  claimed: readonly Record<string, unknown>[],
  results: Record<
    string,
    (args: Readonly<Record<string, unknown>>) => unknown
  > = {},
) {
  const calls: Call[] = [];
  let batches = [claimed];
  const transport: BlockTransport = {
    async call(schema, fn, args) {
      calls.push({ schema, fn, args });
      if (fn === "claim_webhook_deliveries") {
        const [next = [], ...rest] = batches;
        batches = rest;
        return next;
      }
      if (fn === "webhook_secrets") return [SECRET];
      if (fn === "complete_webhook_delivery")
        return results[fn]?.(args) ?? "completed";
      const result = results[fn];
      if (!result) throw new Error(`unexpected ${fn}`);
      return result(args);
    },
  };
  const outcomes = () =>
    calls
      .filter((call) => call.fn === "complete_webhook_delivery")
      .map((call) => call.args["outcome"] as Record<string, unknown>);
  return {
    transport,
    calls,
    outcomes,
    queue: (rows: Record<string, unknown>[]) => batches.push(rows),
  };
}

function fakeHttp(
  respond: (request: WebhookRequest) => WebhookResponse | Error,
) {
  const sent: WebhookRequest[] = [];
  const http: WebhookTransport = {
    apiVersion: 1,
    name: "fake",
    async send(request) {
      sent.push(request);
      const response = respond(request);
      if (response instanceof Error) throw response;
      return response;
    },
  };
  return { http, sent };
}

const ok = () => ({ status: 200, body: "ok" });

const outcomeOf = (calls: readonly Call[], id: string) =>
  calls.find(
    (call) =>
      call.fn === "complete_webhook_delivery" && call.args["delivery"] === id,
  )?.args["outcome"] as Record<string, unknown> | undefined;

function setup(
  claimed: readonly Record<string, unknown>[],
  respond: Parameters<typeof fakeHttp>[0] = ok,
  options: Partial<WebhooksOptions> = {},
  results?: Parameters<typeof fakeBlock>[1],
) {
  const block = fakeBlock(claimed, results);
  const { http, sent } = fakeHttp(respond);
  const events = new EventHub();
  const seen: { type: string; data: unknown }[] = [];
  events.on("block", (event) =>
    seen.push({ type: event.type, data: event.data }),
  );
  const webhooks = createWebhooks({
    transport: block.transport,
    http,
    events,
    ...options,
  });
  return { ...block, sent, seen, webhooks };
}

describe("createWebhooks: deliver", () => {
  it("signs the Standard Webhooks envelope and completes the delivery", async () => {
    const { webhooks, sent, outcomes, seen, calls } = setup([row()]);
    expect(await webhooks.deliver()).toEqual({
      succeeded: 1,
      retrying: 0,
      dead: 0,
      canceled: 0,
      disabled: 0,
    });
    const request = sent[0]!;
    expect(JSON.parse(request.body)).toEqual({
      type: "invoice.paid",
      timestamp: "2026-10-03T10:00:00Z",
      data: { id: 7 },
    });
    expect(request.headers["webhook-id"]).toBe("del-1");
    expect((await verifyWebhook(request, SECRET)).ok).toBe(true);
    expect(outcomes()).toEqual([
      {
        status: "succeeded",
        attempt: 1,
        response_status: 200,
        response_body: "ok",
        duration_ms: expect.any(Number),
      },
    ]);
    expect(calls[0]).toEqual({
      schema: "better_supabase",
      fn: "claim_webhook_deliveries",
      args: { max_items: 25, lease: "2 minutes", max_attempts: 8 },
    });
    expect(seen).toEqual([
      {
        type: "webhook.delivered",
        data: {
          endpointId: "dest-1",
          deliveryId: "del-1",
          eventType: "invoice.paid",
          attempt: 1,
          status: 200,
        },
      },
    ]);
  });

  it("retries retryable statuses with backoff and dead-letters after maxAttempts", async () => {
    const { webhooks, calls, seen } = setup(
      [row(), row({ id: "del-2", attempt: 8 }), row({ id: "del-3" })],
      (request) =>
        request.headers["webhook-id"] === "del-3"
          ? { status: 410, body: "gone" }
          : { status: 503, body: "x".repeat(3000) },
    );
    const before = Date.now();
    expect(await webhooks.deliver()).toMatchObject({
      retrying: 1,
      dead: 2,
    });
    const [retry, last, gone] = ["del-1", "del-2", "del-3"].map((id) =>
      outcomeOf(calls, id),
    );
    expect(retry).toMatchObject({
      status: "retrying",
      attempt: 1,
      response_status: 503,
      error: "HTTP 503",
    });
    expect(String(retry!["response_body"])).toHaveLength(2000);
    const retryAt = Date.parse(String(retry!["retry_at"]));
    expect(retryAt - before).toBeGreaterThanOrEqual(-1000);
    expect(retryAt - before).toBeLessThan(6000);
    expect(last).toMatchObject({ status: "dead", attempt: 8 });
    expect(last).not.toHaveProperty("retry_at");
    expect(gone).toMatchObject({
      status: "dead",
      response_status: 410,
    });
    expect(seen.map((event) => event.type)).toEqual([
      "webhook.failed",
      "webhook.failed",
      "webhook.failed",
    ]);
    expect(seen.map((event) => event.data)).toContainEqual(
      expect.objectContaining({ status: 503, error: "HTTP 503" }),
    );
  });

  it("retries network errors and never retries a policy rejection", async () => {
    const { webhooks, outcomes, calls } = setup(
      [row(), row({ id: "del-2" })],
      (request) =>
        request.headers["webhook-id"] === "del-1"
          ? new Error("socket hang up")
          : new WebhookPolicyError("Endpoint URL is not allowed"),
    );
    expect(await webhooks.deliver()).toMatchObject({
      retrying: 1,
      dead: 1,
    });
    expect(outcomes()).toHaveLength(2);
    expect(outcomeOf(calls, "del-1")).toMatchObject({
      status: "retrying",
      error: "socket hang up",
    });
    expect(outcomeOf(calls, "del-2")).toMatchObject({
      status: "dead",
      error: "Endpoint URL is not allowed",
    });
  });

  it("takes a custom retry policy", async () => {
    const { webhooks, outcomes } = setup(
      [row({ attempt: 2 })],
      () => ({ status: 400, body: "" }),
      {
        retry: {
          maxAttempts: 3,
          backoff: () => 5,
          retryable: (status) => status === 400,
        },
      },
    );
    await webhooks.deliver();
    expect(outcomes()[0]).toMatchObject({ status: "retrying", attempt: 2 });
  });

  it("cancels when shouldDeliver returns false or throws, without sending", async () => {
    const { webhooks, outcomes, sent } = setup(
      [row(), row({ id: "del-2" })],
      ok,
      {
        shouldDeliver: (delivery) => {
          if (delivery.id === "del-2") throw new Error("tenant suspended");
          return false;
        },
      },
    );
    expect(await webhooks.deliver()).toMatchObject({ canceled: 2 });
    expect(sent).toHaveLength(0);
    expect(outcomes()).toHaveLength(2);
    expect(outcomes()).toEqual(
      expect.arrayContaining([
        { status: "canceled", attempt: 1, error: "Canceled by shouldDeliver" },
        { status: "canceled", attempt: 1, error: "tenant suspended" },
      ]),
    );
  });

  it("uses transform, headers, signer and secrets from the options", async () => {
    const { webhooks, sent } = setup(
      [row({ run_id: "run-9", tenant: null, event_id: null })],
      ok,
      {
        transform: (delivery) => ({
          kind: delivery.type,
          runId: delivery.runId,
          body: delivery.payload,
        }),
        headers: (delivery) => ({ "idempotency-key": delivery.id }),
        signer: {
          apiVersion: 1,
          name: "test",
          sign: ({ secrets }) => ({ "x-sig": secrets.join("|") }),
        },
        secrets: { apiVersion: 1, secrets: async () => ["a", "b"] },
      },
    );
    await webhooks.deliver();
    expect(JSON.parse(sent[0]!.body)).toEqual({
      kind: "invoice.paid",
      runId: "run-9",
      body: { id: 7 },
    });
    expect(sent[0]!.headers).toEqual({
      "content-type": "application/json",
      "user-agent": "better-supabase-webhooks",
      "idempotency-key": "del-1",
      "x-sig": "a|b",
    });
  });

  it("dead-letters an endpoint without secrets and retries a failing transform", async () => {
    const empty = setup([row()], ok, {
      secrets: { apiVersion: 1, secrets: async () => [] },
    });
    expect(await empty.webhooks.deliver()).toMatchObject({ dead: 1 });
    expect(empty.outcomes()[0]).toMatchObject({
      error: "The endpoint has no signing secret",
    });

    const broken = setup([row()], ok, {
      transform: () => {
        throw new Error("bad payload");
      },
    });
    expect(await broken.webhooks.deliver()).toMatchObject({ retrying: 1 });
    expect(broken.sent).toHaveLength(0);
  });

  it("waits as long as Retry-After asks, up to a day", async () => {
    const { webhooks, calls } = setup(
      [row(), row({ id: "del-2" })],
      (request) => ({
        status: 429,
        body: "",
        retryAfter: request.headers["webhook-id"] === "del-1" ? 600 : 999_999,
      }),
    );
    const before = Date.now();
    await webhooks.deliver();
    const [short, long] = ["del-1", "del-2"].map(
      (id) => Date.parse(String(outcomeOf(calls, id)?.["retry_at"])) - before,
    );
    expect(short).toBeGreaterThanOrEqual(599_000);
    expect(short).toBeLessThan(602_000);
    expect(long).toBeLessThan(86_402_000);
    expect(long).toBeGreaterThan(86_398_000);
  });

  it("drops the result of a delivery whose lease another worker took", async () => {
    const { webhooks, seen } = setup(
      [row()],
      ok,
      {},
      { complete_webhook_delivery: () => "stale" },
    );
    expect(await webhooks.deliver()).toMatchObject({ succeeded: 0 });
    expect(seen).toEqual([]);
  });

  it("sends a batch with at most concurrency requests in flight", async () => {
    let inFlight = 0;
    let peak = 0;
    const block = fakeBlock(
      Array.from({ length: 7 }, (_, index) =>
        row({ id: `del-${String(index)}` }),
      ),
    );
    const webhooks = createWebhooks({
      transport: block.transport,
      http: {
        apiVersion: 1,
        name: "slow",
        async send() {
          inFlight += 1;
          peak = Math.max(peak, inFlight);
          await new Promise((resolve) => {
            setTimeout(resolve, 5);
          });
          inFlight -= 1;
          return { status: 200, body: "" };
        },
      },
    });
    expect(await webhooks.deliver({ concurrency: 3 })).toMatchObject({
      succeeded: 7,
    });
    expect(peak).toBe(3);
  });

  it("counts and announces an endpoint the block disabled", async () => {
    const { webhooks, seen } = setup(
      [row()],
      () => ({ status: 400, body: "" }),
      {},
      {
        complete_webhook_delivery: () => "disabled",
      },
    );
    expect(await webhooks.deliver()).toMatchObject({
      dead: 1,
      disabled: 1,
    });
    expect(seen.map((event) => event.type)).toEqual([
      "webhook.failed",
      "webhook.disabled",
    ]);
  });

  it("claims again while batches are full and stops at the budget", async () => {
    const block = setup([row(), row({ id: "del-2" })], ok, { schema: "hooks" });
    block.queue([row({ id: "del-3" })]);
    expect(
      await block.webhooks.deliver({ batch: 2, lease: "30 seconds" }),
    ).toMatchObject({ succeeded: 3 });
    expect(
      block.calls.filter((call) => call.fn === "claim_webhook_deliveries"),
    ).toHaveLength(2);
    expect(block.calls.every((call) => call.schema === "hooks")).toBe(true);

    const idle = setup([row()]);
    expect(await idle.webhooks.deliver({ budgetMs: 0 })).toMatchObject({
      succeeded: 0,
    });
    expect(idle.calls).toHaveLength(0);
  });

  it("ignores rows that aren't objects and fills defaults", async () => {
    const { webhooks, sent } = setup([
      "junk" as unknown as Record<string, unknown>,
      row({ payload: null, attempt: null, created_at: null }),
    ]);
    expect(await webhooks.deliver()).toMatchObject({ succeeded: 1 });
    expect(JSON.parse(sent[0]!.body).data).toEqual({});
  });
});

describe("createWebhooks: management", () => {
  it("publishes, dispatches, redelivers and rotates through the block functions", async () => {
    const { webhooks, calls } = setup(
      [],
      ok,
      {},
      {
        publish_webhook_event: () => 2,
        dispatch_webhook: () => "del-9",
        redeliver_webhook: () => "del-1",
        rotate_webhook_secret: () => "whsec_new",
      },
    );
    expect(
      await webhooks
        .publish({
          type: "invoice.paid",
          data: { id: 7 },
          tenant: "org-1",
          id: "evt-1",
        })
        .orThrow(),
    ).toBe(2);
    expect(
      await webhooks
        .dispatch({
          endpointId: "dest-1",
          type: "run.done",
          data: undefined,
          runId: "run-1",
        })
        .orThrow(),
    ).toBe("del-9");
    expect(await webhooks.redeliver("del-1").orThrow()).toBe("del-1");
    expect(
      await webhooks.rotateSecret("dest-1", { overlap: "1 hour" }).orThrow(),
    ).toBe("whsec_new");
    expect(calls.map(({ fn, args }) => [fn, args])).toEqual([
      [
        "publish_webhook_event",
        {
          event_type: "invoice.paid",
          payload: { id: 7 },
          tenant: "org-1",
          event_id: "evt-1",
        },
      ],
      [
        "dispatch_webhook",
        {
          endpoint: "dest-1",
          event_type: "run.done",
          payload: {},
          run_id: "run-1",
          event_id: null,
        },
      ],
      ["redeliver_webhook", { delivery: "del-1" }],
      ["rotate_webhook_secret", { endpoint: "dest-1", overlap: "1 hour" }],
    ]);
  });

  it("maps database errors to DbError results", async () => {
    const { webhooks } = setup(
      [],
      ok,
      {},
      {
        dispatch_webhook: () => {
          throw Object.assign(new Error("Endpoint is disabled"), {
            code: "55000",
            hint: "WEBHOOK_ENDPOINT_DISABLED",
          });
        },
        publish_webhook_event: () => {
          throw new TypeError("boom");
        },
      },
    );
    const dispatched = await webhooks.dispatch({
      endpointId: "d",
      type: "t",
      data: {},
    });
    expect(dispatched.ok).toBe(false);
    expect(!dispatched.ok && dispatched.error.message).toBe(
      "Endpoint is disabled",
    );
    expect((await webhooks.publish({ type: "t", data: {} })).ok).toBe(false);
  });

  it("refuses to rotate with a store that can't", async () => {
    const { webhooks } = setup([], ok, {
      secrets: { apiVersion: 1, secrets: async () => [] },
    });
    const result = await webhooks.rotateSecret("dest-1");
    expect(!result.ok && result.error.message).toBe(
      "The secret store can't rotate secrets",
    );
  });

  it("publishes CloudEvents from the sink with the partition key as tenant", async () => {
    const { webhooks, calls } = setup(
      [],
      ok,
      {},
      { publish_webhook_event: () => 1 },
    );
    await webhooks.sink().send([
      {
        specversion: "1.0",
        id: "ce-1",
        source: "/crm",
        type: "deal.won",
        data: { id: 1 },
        partitionkey: "org-1",
      },
      { specversion: "1.0", id: "ce-2", source: "/crm", type: "deal.lost" },
    ]);
    expect(calls.map((call) => call.args)).toEqual([
      {
        event_type: "deal.won",
        payload: { id: 1 },
        tenant: "org-1",
        event_id: "ce-1",
      },
      { event_type: "deal.lost", payload: {}, tenant: null, event_id: "ce-2" },
    ]);
  });

  it("removes the relay's type prefix before publishing", async () => {
    const { webhooks, calls } = setup(
      [],
      ok,
      {},
      { publish_webhook_event: () => 1 },
    );
    const event = (type: string) => ({
      specversion: "1.0" as const,
      id: type,
      source: "/crm",
      type,
    });
    await webhooks
      .sink()
      .send([
        event("dev.better-supabase.deal.won"),
        event("com.acme.deal.won"),
      ]);
    await webhooks
      .sink({ typePrefix: "com.acme" })
      .send([event("com.acme.deal.lost")]);
    expect(calls.map((call) => call.args["event_type"])).toEqual([
      "deal.won",
      "com.acme.deal.won",
      "deal.lost",
    ]);
  });
});

describe("createWebhooks: deliverRoute", () => {
  it("needs a secret", () => {
    const { webhooks } = setup([]);
    expect(() => webhooks.deliverRoute({ secret: undefined })).toThrow(
      "needs a secret",
    );
  });

  it("checks the method and bearer secret, then delivers", async () => {
    const { webhooks } = setup([row()]);
    const route = webhooks.deliverRoute({ secret: "cron-secret" });
    const url = "https://app.example.com/api/webhooks/deliver";
    expect((await route(new Request(url, { method: "PUT" }))).status).toBe(405);
    const denied = await route(new Request(url));
    expect(denied.status).toBe(401);
    expect(denied.headers.get("content-type")).toContain(
      "application/problem+json",
    );
    const response = await route(
      new Request(url, { headers: { authorization: "Bearer cron-secret" } }),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ succeeded: 1 });
  });

  it("reports a failing run as a problem", async () => {
    const failures: unknown[] = [];
    const webhooks = createWebhooks({
      transport: {
        call: async () => {
          throw new Error("db down");
        },
      },
      http: fakeHttp(ok).http,
    });
    const route = webhooks.deliverRoute({
      secret: "s",
      onError: (error) => failures.push(error),
    });
    const response = await route(
      new Request("https://app.example.com/cron", {
        method: "POST",
        headers: { authorization: "Bearer s" },
      }),
    );
    expect(response.status).toBe(500);
    expect(failures).toHaveLength(1);
  });
});

describe("sqlSecretStore", () => {
  it("reads and rotates through the block functions and passes the conformance kit", async () => {
    let secrets: string[] = ["whsec_first"];
    const calls: Call[] = [];
    const store = sqlSecretStore(
      {
        async call(schema, fn, args) {
          calls.push({ schema, fn, args });
          if (fn === "webhook_secrets") return [...secrets, 42];
          const next = `whsec_${String(secrets.length)}`;
          secrets = [next, ...secrets];
          return next;
        },
      },
      { schema: "hooks" },
    );
    const report = await testWebhookSecretStore(store, {
      endpointId: "dest-1",
    });
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(calls[0]).toEqual({
      schema: "hooks",
      fn: "webhook_secrets",
      args: { endpoint: "dest-1" },
    });
    expect(calls[1]).toEqual({
      schema: "hooks",
      fn: "rotate_webhook_secret",
      args: { endpoint: "dest-1", overlap: "1 hour" },
    });
  });

  it("fails the block when rotation drops the previous secret", async () => {
    let current = "whsec_0";
    let count = 0;
    await expect(
      testWebhookSecretStore(
        {
          apiVersion: 1,
          secrets: async () => [current],
          rotate: async () => {
            count += 1;
            current = `whsec_${String(count)}`;
            return current;
          },
        },
        { endpointId: "dest-1" },
      ),
    ).rejects.toThrow("the previous secret must keep signing");
  });
});
