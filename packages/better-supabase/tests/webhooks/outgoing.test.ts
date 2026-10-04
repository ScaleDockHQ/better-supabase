import { describe, expect, it } from "vitest";

import type { KitTransport } from "../../src/core/kit-transport.ts";
import type {
  WebhookRequest,
  WebhookTransport,
  WebhooksOptions,
} from "../../src/webhooks/index.ts";

import { EventHub } from "../../src/core/events.ts";
import { testWebhookSecretStore } from "../../src/testing/index.ts";
import {
  createWebhooks,
  sqlSecretStore,
  verifyWebhook,
  WebhookPolicyError,
} from "../../src/webhooks/index.ts";

const SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";

interface Call {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: "del-1",
    destination_id: "dest-1",
    url: "https://hooks.example.com/in",
    type: "invoice.paid",
    payload: { id: 7 },
    attempt: 0,
    tenant: "org-1",
    event_id: "evt-1",
    run_id: null,
    created_at: "2026-10-03T10:00:00Z",
    ...overrides,
  };
}

/** Serves `claimed` once, then nothing; answers the rest from `results`. */
function fakeKit(
  claimed: readonly Record<string, unknown>[],
  results: Record<
    string,
    (args: Readonly<Record<string, unknown>>) => unknown
  > = {},
) {
  const calls: Call[] = [];
  let batches = [claimed];
  const transport: KitTransport = {
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
  respond: (
    request: WebhookRequest,
  ) => { status: number; body: string } | Error,
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

function setup(
  claimed: readonly Record<string, unknown>[],
  respond: Parameters<typeof fakeHttp>[0] = ok,
  options: Partial<WebhooksOptions> = {},
  results?: Parameters<typeof fakeKit>[1],
) {
  const kit = fakeKit(claimed, results);
  const { http, sent } = fakeHttp(respond);
  const events = new EventHub();
  const seen: { type: string; data: unknown }[] = [];
  events.on("kit", (event) =>
    seen.push({ type: event.type, data: event.data }),
  );
  const webhooks = createWebhooks({
    transport: kit.transport,
    http,
    events,
    ...options,
  });
  return { ...kit, sent, seen, webhooks };
}

describe("createWebhooks: deliver", () => {
  it("signs the Standard Webhooks envelope and completes the delivery", async () => {
    const { webhooks, sent, outcomes, seen, calls } = setup([row()]);
    expect(await webhooks.deliver()).toEqual({
      completed: 1,
      failed: 0,
      deadLettered: 0,
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
        status: "completed",
        attempt: 1,
        response_status: 200,
        response_body: "ok",
        duration_ms: expect.any(Number),
      },
    ]);
    expect(calls[0]).toEqual({
      schema: "better_supabase",
      fn: "claim_webhook_deliveries",
      args: { max_items: 25, lease: "2 minutes" },
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
    const { webhooks, outcomes, seen } = setup(
      [row(), row({ id: "del-2", attempt: 4 }), row({ id: "del-3" })],
      (request) =>
        request.headers["webhook-id"] === "del-3"
          ? { status: 410, body: "gone" }
          : { status: 503, body: "x".repeat(3000) },
    );
    const before = Date.now();
    expect(await webhooks.deliver()).toMatchObject({
      failed: 1,
      deadLettered: 2,
    });
    const [retry, last, gone] = outcomes();
    expect(retry).toMatchObject({
      status: "failed",
      attempt: 1,
      response_status: 503,
      error: "HTTP 503",
    });
    expect(String(retry!["response_body"])).toHaveLength(2000);
    const retryAt = Date.parse(String(retry!["retry_at"]));
    expect(retryAt - before).toBeGreaterThanOrEqual(29_000);
    expect(retryAt - before).toBeLessThan(40_000);
    expect(last).toMatchObject({ status: "dead_lettered", attempt: 5 });
    expect(last).not.toHaveProperty("retry_at");
    expect(gone).toMatchObject({
      status: "dead_lettered",
      response_status: 410,
    });
    expect(seen.map((event) => event.type)).toEqual([
      "webhook.failed",
      "webhook.failed",
      "webhook.failed",
    ]);
    expect(seen[0]!.data).toMatchObject({ status: 503, error: "HTTP 503" });
  });

  it("retries network errors and never retries a policy rejection", async () => {
    const { webhooks, outcomes } = setup(
      [row(), row({ id: "del-2" })],
      (request) =>
        request.headers["webhook-id"] === "del-1"
          ? new Error("socket hang up")
          : new WebhookPolicyError("Destination URL is not allowed"),
    );
    expect(await webhooks.deliver()).toMatchObject({
      failed: 1,
      deadLettered: 1,
    });
    expect(outcomes()).toEqual([
      expect.objectContaining({ status: "failed", error: "socket hang up" }),
      expect.objectContaining({
        status: "dead_lettered",
        error: "Destination URL is not allowed",
      }),
    ]);
  });

  it("takes a custom retry policy", async () => {
    const { webhooks, outcomes } = setup(
      [row({ attempt: 1 })],
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
    expect(outcomes()[0]).toMatchObject({ status: "failed", attempt: 2 });
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
    expect(outcomes()).toEqual([
      { status: "canceled", attempt: 0, error: "Canceled by shouldDeliver" },
      { status: "canceled", attempt: 0, error: "tenant suspended" },
    ]);
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

  it("dead-letters a destination without secrets and retries a failing transform", async () => {
    const empty = setup([row()], ok, {
      secrets: { apiVersion: 1, secrets: async () => [] },
    });
    expect(await empty.webhooks.deliver()).toMatchObject({ deadLettered: 1 });
    expect(empty.outcomes()[0]).toMatchObject({
      error: "The destination has no signing secret",
    });

    const broken = setup([row()], ok, {
      transform: () => {
        throw new Error("bad payload");
      },
    });
    expect(await broken.webhooks.deliver()).toMatchObject({ failed: 1 });
    expect(broken.sent).toHaveLength(0);
  });

  it("counts and announces a destination the kit disabled", async () => {
    const { webhooks, seen } = setup(
      [row()],
      () => ({ status: 400, body: "" }),
      {},
      {
        complete_webhook_delivery: () => "disabled",
      },
    );
    expect(await webhooks.deliver()).toMatchObject({
      deadLettered: 1,
      disabled: 1,
    });
    expect(seen.map((event) => event.type)).toEqual([
      "webhook.failed",
      "webhook.disabled",
    ]);
  });

  it("claims again while batches are full and stops at the budget", async () => {
    const kit = setup([row(), row({ id: "del-2" })], ok, { schema: "hooks" });
    kit.queue([row({ id: "del-3" })]);
    expect(
      await kit.webhooks.deliver({ batch: 2, lease: "30 seconds" }),
    ).toMatchObject({ completed: 3 });
    expect(
      kit.calls.filter((call) => call.fn === "claim_webhook_deliveries"),
    ).toHaveLength(2);
    expect(kit.calls.every((call) => call.schema === "hooks")).toBe(true);

    const idle = setup([row()]);
    expect(await idle.webhooks.deliver({ budgetMs: 0 })).toMatchObject({
      completed: 0,
    });
    expect(idle.calls).toHaveLength(0);
  });

  it("ignores rows that aren't objects and fills defaults", async () => {
    const { webhooks, sent } = setup([
      "junk" as unknown as Record<string, unknown>,
      row({ payload: null, attempt: null, created_at: null }),
    ]);
    expect(await webhooks.deliver()).toMatchObject({ completed: 1 });
    expect(JSON.parse(sent[0]!.body).data).toEqual({});
  });
});

describe("createWebhooks: management", () => {
  it("publishes, dispatches, redelivers and rotates through the kit functions", async () => {
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
          destinationId: "dest-1",
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
          destination: "dest-1",
          event_type: "run.done",
          payload: {},
          run_id: "run-1",
          event_id: null,
        },
      ],
      ["redeliver_webhook", { delivery: "del-1" }],
      ["rotate_webhook_secret", { destination: "dest-1", overlap: "1 hour" }],
    ]);
  });

  it("maps database errors to DbError results", async () => {
    const { webhooks } = setup(
      [],
      ok,
      {},
      {
        dispatch_webhook: () => {
          throw Object.assign(new Error("Destination is disabled"), {
            code: "55000",
            hint: "WEBHOOK_DESTINATION_DISABLED",
          });
        },
        publish_webhook_event: () => {
          throw new TypeError("boom");
        },
      },
    );
    const dispatched = await webhooks.dispatch({
      destinationId: "d",
      type: "t",
      data: {},
    });
    expect(dispatched.ok).toBe(false);
    expect(!dispatched.ok && dispatched.error.message).toBe(
      "Destination is disabled",
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
    expect(await response.json()).toMatchObject({ completed: 1 });
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
  it("reads and rotates through the kit functions and passes the conformance kit", async () => {
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
      destinationId: "dest-1",
    });
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(calls[0]).toEqual({
      schema: "hooks",
      fn: "webhook_secrets",
      args: { destination: "dest-1" },
    });
    expect(calls[1]).toEqual({
      schema: "hooks",
      fn: "rotate_webhook_secret",
      args: { destination: "dest-1", overlap: "1 hour" },
    });
  });

  it("fails the kit when rotation drops the previous secret", async () => {
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
        { destinationId: "dest-1" },
      ),
    ).rejects.toThrow("the previous secret must keep signing");
  });
});
