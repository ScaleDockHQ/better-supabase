import { describe, expect, it, vi } from "vitest";

import type {
  WebhookRequest,
  WebhookResponse,
  WebhookTransport,
  WebhooksOptions,
} from "../../../src/blocks/webhooks/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";
import type {
  Subscriber,
  SubscriberEvent,
  SubscriberPolicy,
} from "../../../src/core/contracts/authorization-hooks.ts";
import type { CredentialProvider } from "../../../src/credentials/provider.ts";

import {
  createWebhooks,
  sqlSecretStore,
  verifyWebhook,
  UrlCheckError,
  WebhookPolicyError,
} from "../../../src/blocks/webhooks/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { EventHub } from "../../../src/core/events.ts";
import { AsyncResult } from "../../../src/core/result.ts";
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

      if (fn === "webhook_secrets") {
        return [SECRET];
      }

      if (fn === "complete_webhook_delivery") {
        return results[fn]?.(args) ?? "completed";
      }

      const result = results[fn];

      if (!result) {
        throw new Error(`unexpected ${fn}`);
      }

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

      if (response instanceof Error) {
        throw response;
      }

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
  it("signs a structured CloudEvent and completes the delivery", async () => {
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
      specversion: "1.0",
      id: "del-1",
      source: "urn:better-supabase:webhooks",
      type: "invoice.paid",
      time: "2026-10-03T10:00:00Z",
      datacontenttype: "application/json",
      data: { id: 7 },
    });
    expect(request.headers["content-type"]).toBe(
      "application/cloudevents+json",
    );
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

  it("waits at least half the step, and at least a second, before a retry", async () => {
    const random = vi.spyOn(Math, "random").mockReturnValue(0);

    try {
      const { webhooks, calls } = setup(
        [row(), row({ id: "del-2", attempt: 3 })],
        () => ({ status: 503, body: "" }),
      );

      const before = Date.now();
      await webhooks.deliver();

      const waits = ["del-1", "del-2"].map(
        (id) =>
          (Date.parse(String(outcomeOf(calls, id)!["retry_at"])) - before) /
          1000,
      );

      expect(waits[0]).toBeGreaterThanOrEqual(1.5);
      expect(waits[0]).toBeLessThan(4);
      expect(waits[1]).toBeGreaterThanOrEqual(899);
      expect(waits[1]).toBeLessThan(902);
      random.mockReturnValue(0.999999);

      const { webhooks: later, calls: laterCalls } = setup([row()], () => ({
        status: 503,
        body: "",
      }));

      const start = Date.now();
      await later.deliver();

      const wait =
        Date.parse(String(outcomeOf(laterCalls, "del-1")!["retry_at"])) - start;

      expect(wait).toBeGreaterThanOrEqual(4000);
      expect(wait).toBeLessThan(6000);
    } finally {
      random.mockRestore();
    }
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
    expect(await webhooks.deliver()).toMatchObject({ retrying: 1, dead: 2 });

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
    expect(gone).toMatchObject({ status: "dead", response_status: 410 });
    expect(seen.map((event) => event.type)).toEqual([
      "webhook.failed",
      "webhook.failed",
      "webhook.failed",
    ]);
    expect(seen.map((event) => event.data)).toContainEqual(
      expect.objectContaining({ status: 503, error: "HTTP 503" }),
    );
  });

  it("retries network errors and failed URL checks, never a policy rejection", async () => {
    const { webhooks, outcomes, calls } = setup(
      [row(), row({ id: "del-2" }), row({ id: "del-3" })],
      (request) =>
        request.headers["webhook-id"] === "del-1"
          ? new Error("socket hang up")
          : request.headers["webhook-id"] === "del-3"
            ? new UrlCheckError("Could not check endpoint URL: a.test")
            : new WebhookPolicyError("Endpoint URL is not allowed"),
    );

    expect(await webhooks.deliver()).toMatchObject({ retrying: 2, dead: 1 });
    expect(outcomes()).toHaveLength(3);
    expect(outcomeOf(calls, "del-3")).toMatchObject({
      status: "retrying",
      error: "Could not check endpoint URL: a.test",
    });
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
          if (delivery.id === "del-2") {
            throw new Error("tenant suspended");
          }

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
    expect(JSON.parse(sent[0]!.body).data).toEqual({
      kind: "invoice.paid",
      runId: "run-9",
      body: { id: 7 },
    });
    expect(sent[0]!.headers).toEqual({
      "content-type": "application/cloudevents+json",
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

  it("signs v1a endpoints with the asymmetric signer, without secrets", async () => {
    const unsigned = setup([row({ signing: "v1a" })]);
    expect(await unsigned.webhooks.deliver()).toMatchObject({ dead: 1 });
    expect(unsigned.outcomes()[0]).toMatchObject({
      error: "The endpoint signs with v1a, but no asymmetricSigner is set",
    });

    const signed = setup([row({ signing: "v1a" }), row({ id: "del-2" })], ok, {
      secrets: { apiVersion: 1, secrets: async () => [] },
      asymmetricSigner: {
        apiVersion: 1,
        name: "test-v1a",
        sign: () => ({ "webhook-signature": "v1a,sig" }),
      },
    });

    expect(await signed.webhooks.deliver()).toMatchObject({
      succeeded: 1,
      dead: 1,
    });
    expect(signed.sent).toHaveLength(1);
    expect(signed.sent[0]!.headers["webhook-signature"]).toBe("v1a,sig");
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
      { complete_webhook_delivery: () => "disabled" },
    );

    expect(await webhooks.deliver()).toMatchObject({ dead: 1, disabled: 1 });
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

describe("createWebhooks: CloudEvents", () => {
  const TRACE = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

  it("sets source from appUrl, subject, dataschema, a type prefix and traceparent", async () => {
    const { webhooks, sent } = setup(
      [row({ subject: "invoices/7" }), row({ id: "del-2", type: "deal.won" })],
      ok,
      {
        appUrl: "https://app.example.com/dashboard",
        typePrefix: "com.example.",
        dataschema: (delivery) =>
          delivery.type === "invoice.paid"
            ? "https://app.example.com/schemas/invoice-paid.json"
            : undefined,
        traceparent: (delivery) =>
          delivery.id === "del-1" ? TRACE : "not-a-trace",
      },
    );

    await webhooks.deliver();

    const [first, second] = ["del-1", "del-2"].map((id) =>
      JSON.parse(
        sent.find((request) => request.headers["webhook-id"] === id)!.body,
      ),
    );

    expect(first).toMatchObject({
      source: "https://app.example.com/webhooks",
      type: "com.example.invoice.paid",
      subject: "invoices/7",
      dataschema: "https://app.example.com/schemas/invoice-paid.json",
      traceparent: TRACE,
    });
    expect(second).not.toHaveProperty("subject");
    expect(second).not.toHaveProperty("dataschema");
    expect(second).not.toHaveProperty("traceparent");
  });

  it("refuses a source or dataschema that is not an absolute URI", () => {
    const transport = fakeBlock([]).transport;
    expect(() => createWebhooks({ transport, source: "/events" })).toThrow(
      "createWebhooks: source must be an absolute URI",
    );
    expect(() => createWebhooks({ transport, appUrl: "app.test" })).toThrow(
      "createWebhooks: appUrl must be an absolute URI",
    );
    expect(() => createWebhooks({ transport, dataschema: "x.json" })).toThrow(
      "createWebhooks: dataschema must be an absolute URI",
    );
    expect(
      createWebhooks({ transport, source: "https://crm.test/events" }),
    ).toBeDefined();
  });

  it("retries a delivery whose dataschema function returns a relative URI", async () => {
    const { webhooks, sent, outcomes } = setup([row()], ok, {
      dataschema: () => "schemas/x.json",
    });

    expect(await webhooks.deliver()).toMatchObject({ retrying: 1 });
    expect(sent).toHaveLength(0);
    expect(outcomes()[0]!["error"]).toContain("must be an absolute URI");
  });

  it("sends one signed batch per endpoint that takes batches", async () => {
    const { webhooks, sent, outcomes } = setup(
      [
        row({ batch: true }),
        row({ id: "del-2", batch: true, event_id: "evt-2" }),
        row({ id: "del-3", endpoint_id: "dest-2" }),
      ],
      ok,
    );

    expect(await webhooks.deliver()).toMatchObject({ succeeded: 3 });
    expect(sent).toHaveLength(2);

    const batch = sent.find(
      (request) =>
        request.headers["content-type"] ===
        "application/cloudevents-batch+json",
    )!;

    const events = JSON.parse(batch.body);
    expect(events.map((event: { id: string }) => event.id)).toEqual([
      "del-1",
      "del-2",
    ]);
    expect(batch.headers["webhook-id"]).toMatch(/^batch_[0-9a-f]{32}$/);
    expect((await verifyWebhook(batch, SECRET)).ok).toBe(true);
    expect(outcomes()).toHaveLength(3);

    const again = setup(
      [row({ id: "del-2", batch: true }), row({ batch: true })],
      ok,
    );

    await again.webhooks.deliver();
    expect(again.sent[0]!.headers["webhook-id"]).toBe(
      batch.headers["webhook-id"],
    );
  });

  it("fails every delivery of a batch together", async () => {
    const { webhooks, outcomes } = setup(
      [row({ batch: true }), row({ id: "del-2", batch: true, attempt: 8 })],
      () => ({ status: 503, body: "" }),
    );

    expect(await webhooks.deliver()).toMatchObject({ retrying: 1, dead: 1 });
    expect(
      outcomes()
        .map((outcome) => String(outcome["status"]))
        .toSorted((a, b) => a.localeCompare(b)),
    ).toEqual(["dead", "retrying"]);
  });
});

describe("createWebhooks: subscribers", () => {
  it("cancels deliveries whose endpoint owner the policy leaves out, once per event", async () => {
    const calls: [SubscriberEvent, readonly Subscriber[]][] = [];

    const policy: SubscriberPolicy = (event, subscribers) => {
      calls.push([event, subscribers]);

      return subscribers.filter((subscriber) => subscriber.principal !== "bob");
    };

    const { webhooks, sent, outcomes } = setup(
      [
        row({ owner: "alice", subject: "invoices/7" }),
        row({
          id: "del-2",
          endpoint_id: "dest-2",
          owner: "bob",
          subject: "invoices/7",
        }),
        row({
          id: "del-3",
          endpoint_id: "dest-3",
          owner: null,
          subject: "invoices/7",
        }),
      ],
      ok,
      { subscribers: policy },
    );

    expect(await webhooks.deliver()).toMatchObject({
      succeeded: 2,
      canceled: 1,
    });
    expect(calls).toHaveLength(1);
    const [event, candidates] = calls[0]!;
    expect(event).toMatchObject({
      type: "invoice.paid",
      tenant: "org-1",
      subject: "invoices/7",
      actorId: null,
    });
    expect(
      candidates.map(({ principal, kind }) => ({ principal, kind })),
    ).toEqual([
      { principal: "alice", kind: "user" },
      { principal: "bob", kind: "user" },
      { principal: "dest-3", kind: "service" },
    ]);
    expect(
      sent
        .map((request) => request.headers["webhook-id"] ?? "")
        .toSorted((a, b) => a.localeCompare(b)),
    ).toEqual(["del-1", "del-3"]);
    expect(outcomes()).toContainEqual({
      status: "canceled",
      attempt: 1,
      error: "Refused by the subscriber policy",
    });
  });

  it("checks each delivery against its own stored subject", async () => {
    const subjects: (string | null | undefined)[] = [];

    const { webhooks } = setup(
      [
        row({ owner: "alice", subject: "subjects/invoice/7" }),
        row({
          id: "del-2",
          endpoint_id: "dest-2",
          owner: null,
          principal: "sp-1",
          subject: "subjects/invoice/8",
        }),
      ],
      ok,
      {
        subscribers: (event, subscribers) => {
          subjects.push(event.subject);

          return subscribers.filter(
            (subscriber) => subscriber.principal === "sp-1",
          );
        },
      },
    );

    expect(await webhooks.deliver()).toMatchObject({
      succeeded: 1,
      canceled: 1,
    });
    expect(
      subjects.toSorted((a, b) => String(a).localeCompare(String(b))),
    ).toEqual(["subjects/invoice/7", "subjects/invoice/8"]);
  });

  it("defaults to subjectReaders under authorization without a delivery policy", async () => {
    const alice = "00000000-0000-4000-8000-00000000000a";
    const bob = "00000000-0000-4000-8000-00000000000b";
    const asked: unknown[] = [];

    const { webhooks, sent } = setup(
      [
        row({ owner: alice, subject: "subjects/invoice/7" }),
        row({
          id: "del-2",
          endpoint_id: "dest-2",
          owner: bob,
          subject: "subjects/invoice/7",
        }),
        row({
          id: "del-3",
          endpoint_id: "dest-3",
          owner: bob,
          event_id: "e-2",
        }),
      ],
      ok,
      { authorization: {} },
      {
        subject_types: () => ["invoice"],
        can_subject_for: (args) => {
          asked.push(args);

          return args["member"] === alice;
        },
      },
    );

    expect(await webhooks.deliver()).toMatchObject({
      succeeded: 2,
      canceled: 1,
    });
    expect(asked).toContainEqual({
      member: bob,
      subject_type: "invoice",
      subject_id: "7",
      action: "read",
    });
    expect(
      sent
        .map((request) => request.headers["webhook-id"] ?? "")
        .toSorted((a, b) => a.localeCompare(b)),
    ).toEqual(["del-1", "del-3"]);
  });

  it("reads the policy from authorization.delivery and passes the payload actor", async () => {
    const seen: unknown[] = [];

    const { webhooks, sent } = setup(
      [row({ event_id: null, payload: { actorId: "u-1" } })],
      ok,
      {
        authorization: {
          delivery: {
            subscribers: (event, subscribers) => {
              seen.push(event.actorId);

              return subscribers;
            },
          },
        },
      },
    );

    expect(await webhooks.deliver()).toMatchObject({ succeeded: 1 });
    expect(seen).toEqual(["u-1"]);
    expect(sent).toHaveLength(1);
  });

  it("retries every delivery of an event when the policy throws, and drops copies it returns", async () => {
    const thrown = setup([row(), row({ id: "del-2", attempt: 8 })], ok, {
      subscribers: async () => {
        throw new Error("provider down");
      },
    });

    expect(await thrown.webhooks.deliver()).toMatchObject({
      retrying: 1,
      dead: 1,
    });
    expect(thrown.sent).toHaveLength(0);
    expect(thrown.outcomes()[0]!["error"]).toBe(
      "Subscriber policy failed: provider down",
    );

    const copied = setup([row()], ok, {
      subscribers: (_event, subscribers) =>
        subscribers.map((subscriber) => ({ ...subscriber })),
    });

    expect(await copied.webhooks.deliver()).toMatchObject({ canceled: 1 });
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
          subject: "invoices/7",
          readPermission: "invoices.read",
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
          subject: "invoices/7",
          read_permission: "invoices.read",
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
      {
        publish_webhook_events: (args) =>
          (args["events"] as unknown[]).map(() => ({ count: 1 })),
      },
    );

    await webhooks.sink().send([
      {
        specversion: "1.0",
        id: "ce-1",
        source: "/crm",
        type: "deal.won",
        subject: "deals/1",
        data: { id: 1 },
        partitionkey: "org-1",
      },
      { specversion: "1.0", id: "ce-2", source: "/crm", type: "deal.lost" },
    ]);
    expect(calls.map((call) => [call.fn, call.args])).toEqual([
      [
        "publish_webhook_events",
        {
          events: [
            {
              event_type: "deal.won",
              payload: { id: 1 },
              tenant: "org-1",
              event_id: "ce-1",
              subject: "deals/1",
            },
            {
              event_type: "deal.lost",
              payload: {},
              tenant: null,
              event_id: "ce-2",
            },
          ],
        },
      ],
    ]);
  });

  it("sends one call per batch and throws the first failure after all of them", async () => {
    const { webhooks, calls } = setup(
      [],
      ok,
      {},
      {
        publish_webhook_events: (args) =>
          (args["events"] as { event_id: string }[]).map((event) =>
            event.event_id === "bad"
              ? { error: { code: "42501", message: "denied", hint: null } }
              : { count: 1 },
          ),
      },
    );

    const event = (id: string) => ({
      specversion: "1.0" as const,
      id,
      source: "/crm",
      type: "deal.won",
    });

    await expect(
      webhooks
        .sink()
        .send([
          event("bad"),
          ...Array.from({ length: 1000 }, (_, index) =>
            event(`e${String(index)}`),
          ),
        ]),
    ).rejects.toThrow("denied");
    expect(calls.map((call) => call.fn)).toEqual([
      "publish_webhook_events",
      "publish_webhook_events",
    ]);
    expect(calls[0]?.args["events"]).toHaveLength(1000);
    expect(calls[1]?.args["events"]).toHaveLength(1);
  });

  it("publishes many events with one result each", async () => {
    const { webhooks } = setup(
      [],
      ok,
      {},
      {
        publish_webhook_events: () => [
          { count: 2 },
          {
            error: {
              code: "22023",
              message: "bad type",
              hint: "WEBHOOK_TYPE_REQUIRED",
            },
          },
        ],
      },
    );

    const results = await webhooks
      .publishMany([
        { type: "deal.won", data: {} },
        { type: "", data: {} },
      ])
      .orThrow();

    expect(results[0]).toMatchObject({ ok: true, data: 2 });
    expect(results[1]).toMatchObject({ ok: false });
    expect(await webhooks.publishMany([]).orThrow()).toEqual([]);
  });

  it("removes the relay's type prefix before publishing", async () => {
    const { webhooks, calls } = setup(
      [],
      ok,
      {},
      {
        publish_webhook_events: (args) =>
          (args["events"] as unknown[]).map(() => ({ count: 1 })),
      },
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
    expect(
      calls.flatMap((call) =>
        (call.args["events"] as { event_type: string }[]).map(
          (published) => published.event_type,
        ),
      ),
    ).toEqual(["deal.won", "com.acme.deal.won", "deal.lost"]);
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

          if (fn === "webhook_secrets") {
            return [...secrets, 42];
          }

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

describe("purge", () => {
  it("calls purge_webhook_deliveries with an interval and returns the count", async () => {
    const block = fakeBlock([], { purge_webhook_deliveries: () => 3 });
    const webhooks = createWebhooks({ transport: block.transport });
    expect(
      await webhooks
        .purge({ olderThan: 86_400, includeDead: true, batch: 50 })
        .orThrow(),
    ).toBe(3);
    await webhooks.purgeJob()({}, {} as never, new AbortController().signal);
    expect(block.calls.map((call) => call.args)).toEqual([
      { older_than: "86400 seconds", include_dead: true, batch: 50 },
      { older_than: undefined, include_dead: undefined, batch: undefined },
    ]);
  });
});

describe("createWebhooks: encoders and credentials", () => {
  const credentials = (
    getToken: CredentialProvider["getToken"],
  ): CredentialProvider => ({
    apiVersion: 1,
    name: "test",
    getToken,
    capabilities: () => ({
      userSubjects: false,
      authorization: false,
      revoke: false,
      inbound: false,
    }),
    revoke: () => AsyncResult.ok(false),
  });

  const token = credentials(() =>
    AsyncResult.ok({
      token: "hec-1",
      headers: { authorization: "Bearer hec-1" },
    }),
  );

  const ref = { provider: "test", name: "hec", tenant: "org-1" };

  it("writes the endpoint's format with its credential, unsigned", async () => {
    const run = setup(
      [row({ format: "splunk-hec", credential_ref: ref })],
      () => ({ status: 200, body: '{"text":"Success","code":0}' }),
      { credentials: token },
    );

    expect(await run.webhooks.deliver()).toMatchObject({ succeeded: 1 });
    const [request] = run.sent;
    expect(request!.headers["authorization"]).toBe("Splunk hec-1");
    expect(request!.headers["webhook-signature"]).toBeUndefined();
    expect(JSON.parse(request!.body)).toMatchObject({
      event: { id: "del-1", type: "invoice.paid" },
    });
    expect(run.calls.some((call) => call.fn === "webhook_secrets")).toBe(false);
  });

  it("uses the token's headers for a signed format and lets classify decide", async () => {
    const run = setup(
      [
        row({ credential_ref: ref }),
        row({ id: "del-2", format: "splunk-hec" }),
      ],
      (request) =>
        request.body.includes("sourcetype")
          ? { status: 200, body: '{"text":"Server is busy","code":9}' }
          : ok(),
      { credentials: token },
    );

    expect(await run.webhooks.deliver()).toMatchObject({
      succeeded: 1,
      retrying: 1,
    });

    const signed = run.sent.find(
      (request) => !request.body.includes("sourcetype"),
    );

    expect(signed!.headers["authorization"]).toBe("Bearer hec-1");
    expect(signed!.headers["webhook-signature"]).toMatch(/^v1,/);
    expect(outcomeOf(run.calls, "del-2")).toMatchObject({
      status: "retrying",
      error: "HEC 9: Server is busy",
    });
  });

  it("picks the encoder per endpoint, with transform's data in both formats", async () => {
    const run = setup(
      [
        row({ format: "standard" }),
        row({ id: "del-2", endpoint_id: "dest-2", format: "cloudevents" }),
      ],
      ok,
      { transform: (delivery) => ({ wrapped: delivery.payload }) },
    );

    expect(await run.webhooks.deliver()).toMatchObject({ succeeded: 2 });

    const standard = run.sent.find(
      (request) => request.headers["content-type"] === "application/json",
    );

    const cloud = run.sent.find((request) => request !== standard);
    expect(standard!.headers["content-type"]).toBe("application/json");
    expect(standard!.headers["webhook-signature"]).toMatch(/^v1,/);
    expect(JSON.parse(standard!.body)).toEqual({
      type: "invoice.paid",
      timestamp: "2026-10-03T10:00:00Z",
      data: { wrapped: { id: 7 } },
    });
    expect(cloud!.headers["content-type"]).toBe("application/cloudevents+json");
    expect(JSON.parse(cloud!.body)).toMatchObject({
      specversion: "1.0",
      data: { wrapped: { id: 7 } },
    });
  });

  it("falls back to defaultFormat for a row without a format", async () => {
    const run = setup([row({ format: null }), row({ id: "del-2" })], ok, {
      defaultFormat: "standard",
    });

    expect(await run.webhooks.deliver()).toMatchObject({ succeeded: 2 });
    expect(run.sent.map((request) => request.headers["content-type"])).toEqual([
      "application/json",
      "application/json",
    ]);
    expect(() => setup([], ok, { defaultFormat: "Not A Format" })).toThrow(
      /defaultFormat "Not A Format"/,
    );
  });

  it("dead-letters an unknown format, a foreign ref and a ref without a provider", async () => {
    const unknown = setup([row({ format: "parquet" })]);
    expect(await unknown.webhooks.deliver()).toMatchObject({ dead: 1 });
    expect(unknown.outcomes()[0]).toMatchObject({
      error: 'No encoder for the endpoint format "parquet"',
    });

    const foreign = setup(
      [row({ credential_ref: { provider: "test", tenant: "org-2" } })],
      ok,
      { credentials: token },
    );

    expect(await foreign.webhooks.deliver()).toMatchObject({ dead: 1 });
    expect(foreign.outcomes()[0]!["error"]).toMatch(/outside tenant "org-1"/);

    const appLevel = setup(
      [
        row({
          tenant: null,
          credential_ref: { provider: "test", tenant: "org-2" },
        }),
      ],
      ok,
      { credentials: token },
    );

    expect(await appLevel.webhooks.deliver()).toMatchObject({ dead: 1 });

    const missing = setup([row({ credential_ref: ref })]);
    expect(await missing.webhooks.deliver()).toMatchObject({ dead: 1 });
    expect(missing.outcomes()[0]).toMatchObject({
      error:
        "The endpoint has a credential_ref, but no credentials provider is set",
    });
    expect(missing.sent).toHaveLength(0);
  });

  it("dead-letters a missing credential and retries a provider outage", async () => {
    const gone = setup([row({ credential_ref: ref })], ok, {
      credentials: credentials(() =>
        AsyncResult.err(dbError("not_found", "No credential stored")),
      ),
    });

    expect(await gone.webhooks.deliver()).toMatchObject({ dead: 1 });
    expect(gone.outcomes()[0]).toMatchObject({ error: "No credential stored" });

    const down = setup([row({ credential_ref: ref })], ok, {
      credentials: credentials(() =>
        AsyncResult.err(dbError("network", "Vault is down")),
      ),
    });

    expect(await down.webhooks.deliver()).toMatchObject({ retrying: 1 });
  });

  it("ignores a credential_ref that isn't a ref, and takes custom encoders", async () => {
    const run = setup(
      [row({ format: "lines", credential_ref: "nope" })],
      () => ({ status: 202, body: "" }),
      {
        encoders: [
          {
            apiVersion: 1,
            name: "lines",
            signed: false,
            encode: (events) => ({
              body: events.map((event) => event.id).join("\n"),
              headers: { "content-type": "text/plain" },
            }),
          },
        ],
      },
    );

    expect(await run.webhooks.deliver()).toMatchObject({ succeeded: 1 });
    expect(run.sent[0]).toMatchObject({
      body: "del-1",
      headers: { "content-type": "text/plain" },
    });
  });
});
