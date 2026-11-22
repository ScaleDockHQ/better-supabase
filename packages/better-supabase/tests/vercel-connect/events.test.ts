import { describe, expect, it } from "vitest";

import type {
  ConnectEventDelivery,
  ConnectEventStatus,
  ConnectEventSubscription,
  ConnectEventVerifier,
} from "../../src/vercel-connect/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  connectEventRoute,
  postgresConnectEventSubscriptions,
} from "../../src/vercel-connect/index.ts";

const subscription: ConnectEventSubscription = {
  id: "sub_1",
  tenantId: "org_1",
  connectorId: "scl_linear",
  userId: "user_1",
  name: "issue.created",
  status: "active",
};

const envelope = {
  version: 1,
  deliveryId: "dlv_1",
  subscriptionId: "sub_1",
  source: { type: "mcp", connectorId: "scl_linear" },
  context: { tenantId: "org_1" },
} as const;

const eventDelivery: ConnectEventDelivery = {
  ...envelope,
  event: {
    eventId: "evt_1",
    name: "issue.created",
    timestamp: "2026-11-21T10:00:00Z",
    data: { title: "Bug" },
    cursor: "c1",
  },
};

type Emitted = Parameters<
  Parameters<typeof connectEventRoute>[0]["outbox"]["emit"]
>[0];

function setup(
  over: {
    delivery?: ConnectEventDelivery;
    found?: ConnectEventSubscription | null;
    verify?: ConnectEventVerifier;
    emitFails?: boolean;
  } = {},
) {
  const emitted: Emitted[] = [];
  const statuses: [string, ConnectEventStatus, string | undefined][] = [];
  const outcomes: unknown[] = [];
  const keys = new Map<string, string>();

  const route = connectEventRoute({
    path: "/api/connect/events",
    verify:
      over.verify ?? (() => Promise.resolve(over.delivery ?? eventDelivery)),
    outbox: {
      emit: (input) => {
        emitted.push(input);

        if (over.emitFails === true) {
          return AsyncResult.err(dbError("network", "down"));
        }

        const key = input.key ?? "";
        const id = keys.get(key) ?? `out_${keys.size + 1}`;
        keys.set(key, id);

        return AsyncResult.ok(id);
      },
    },
    subscriptions: {
      get: () =>
        AsyncResult.ok(over.found === undefined ? subscription : over.found),
      setStatus: (id, status, reason) => {
        statuses.push([id, status, reason]);

        return AsyncResult.ok(true);
      },
    },
    onDelivery: (outcome) => {
      outcomes.push(outcome);
    },
  });

  const post = (): Promise<Response> =>
    route(
      new Request("https://app.test/api/connect/events", { method: "POST" }),
    );

  return { route, post, emitted, statuses, outcomes };
}

describe("connectEventRoute", () => {
  it("writes an event to the outbox under the tenant, keyed by the delivery", async () => {
    const { post, emitted, outcomes } = setup();
    const response = await post();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "accepted", id: "out_1" });
    expect(emitted).toEqual([
      {
        type: "connect.issue.created",
        tenant: "org_1",
        subject: "user_1",
        key: "connect:dlv_1",
        source: "vercel-connect",
        payload: expect.objectContaining({
          eventId: "evt_1",
          data: { title: "Bug" },
          deliveryId: "dlv_1",
        }),
      },
    ]);
    expect(outcomes).toEqual([
      {
        deliveryId: "dlv_1",
        subscriptionId: "sub_1",
        status: "accepted",
        tenantId: "org_1",
        type: "connect.issue.created",
      },
    ]);
  });

  it("answers a redelivery with the first event's id", async () => {
    const { post } = setup();

    const first = await (await post()).json();
    const second = await (await post()).json();

    expect(second).toEqual(first);
  });

  it("acknowledges and drops a delivery for an unknown or stopped subscription", async () => {
    for (const found of [
      null,
      { ...subscription, status: "stopped" as const },
    ]) {
      const { post, emitted, outcomes } = setup({ found });
      const response = await post();

      expect(await response.json()).toEqual({ status: "ignored" });
      expect(emitted).toEqual([]);
      expect(outcomes).toHaveLength(1);
    }
  });

  it("answers 503 when the outbox write fails, so Connect retries", async () => {
    const { post } = setup({ emitFails: true });
    const response = await post();

    expect(response.status).toBe(503);
  });

  it("writes a gap as an event a consumer can resync on", async () => {
    const { post, emitted } = setup({
      delivery: {
        ...envelope,
        control: { type: "gap", cursor: "c9", truncated: true },
      },
    });

    expect((await post()).status).toBe(200);
    expect(emitted[0]).toMatchObject({
      type: "connect.gap",
      payload: { cursor: "c9", truncated: true },
    });
  });

  it("marks the subscription failed when Connect ends it", async () => {
    const { post, emitted, statuses } = setup({
      delivery: {
        ...envelope,
        control: {
          type: "terminated",
          error: { code: -32_000, message: "x".repeat(900) },
        },
      },
    });

    expect((await post()).status).toBe(200);
    expect(emitted[0]?.type).toBe("connect.terminated");
    expect(statuses).toEqual([["sub_1", "failed", "x".repeat(500)]]);
  });

  it("maps verification failures to 401, 503 and 500 without writing", async () => {
    const failing =
      (code: string): ConnectEventVerifier =>
      () =>
        Promise.reject(
          Object.assign(new Error("no"), {
            name: "McpEventVerificationError",
            code,
          }),
        );

    const cases: [ConnectEventVerifier, number][] = [
      [failing("invalid_delivery"), 401],
      [failing("verification_unavailable"), 503],
      [failing("configuration_error"), 500],
      [() => Promise.reject(new Error("anything")), 401],
    ];

    for (const [verify, status] of cases) {
      const { post, emitted } = setup({ verify });

      expect((await post()).status).toBe(status);
      expect(emitted).toEqual([]);
    }
  });

  it("rejects other methods and keeps an observer's error away from the response", async () => {
    const { route } = setup();

    expect(
      (await route(new Request("https://app.test/x", { method: "GET" })))
        .status,
    ).toBe(405);

    const throwing = connectEventRoute({
      path: "/p",
      verify: () => Promise.resolve(eventDelivery),
      outbox: { emit: () => AsyncResult.ok("out_1") },
      subscriptions: {
        get: () => AsyncResult.ok(subscription),
        setStatus: () => AsyncResult.ok(true),
      },
      onDelivery: () => {
        throw new Error("boom");
      },
    });

    expect(
      (await throwing(new Request("https://app.test/p", { method: "POST" })))
        .status,
    ).toBe(200);
  });
});

describe("postgresConnectEventSubscriptions", () => {
  function sqlFake(rows: Record<string, unknown>[]) {
    const calls: { text: string; params: unknown[] | undefined }[] = [];

    return {
      calls,
      sql: {
        queryRaw: (text: string, params?: unknown[]) => {
          calls.push({ text, params });

          return Promise.resolve(rows as never);
        },
      },
    };
  }

  it("reads a row into a subscription", async () => {
    const { sql, calls } = sqlFake([
      {
        id: "sub_1",
        tenant_id: "org_1",
        connector_id: "scl_linear",
        user_id: "user_1",
        name: "issue.created",
        status: "active",
        status_reason: null,
        expires_at: new Date(60_000),
        created_at: new Date(0),
      },
    ]);

    const result = await postgresConnectEventSubscriptions(sql).get("sub_1");

    expect(result.ok && result.data).toMatchObject({
      id: "sub_1",
      tenantId: "org_1",
      userId: "user_1",
      status: "active",
    });
    expect(calls[0]?.text).toContain('"public"."connect_event_subscriptions"');
  });

  it("returns null for a missing row and false for a missing update", async () => {
    const { sql } = sqlFake([]);
    const store = postgresConnectEventSubscriptions(sql);
    const found = await store.get("nope");
    const updated = await store.setStatus("nope", "stopped");

    expect(found.ok && found.data).toBeNull();
    expect(updated.ok && updated.data).toBe(false);
  });

  it("returns a network error when the query fails", async () => {
    const store = postgresConnectEventSubscriptions({
      queryRaw: () => Promise.reject(new Error("down")),
    });

    const result = await store.remove("sub_1");

    expect(!result.ok && result.error.kind).toBe("network");
  });

  it("saves, lists and removes subscriptions in the named table", async () => {
    const { sql, calls } = sqlFake([
      {
        id: "sub_2",
        tenant_id: "org_1",
        connector_id: "scl_linear",
        user_id: null,
        name: "issue.created",
        status: "paused",
        status_reason: "token revoked",
        expires_at: "2026-11-01T00:00:00Z",
        created_at: null,
      },
    ]);

    const store = postgresConnectEventSubscriptions(sql, {
      schema: "connect",
      table: "subs",
    });

    await store
      .save({
        id: "sub_1",
        tenantId: "org_1",
        connectorId: "scl_linear",
        name: "issue.created",
        status: "active",
        expiresAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      })
      .orThrow();
    await store
      .save({
        id: "sub_1",
        tenantId: "org_1",
        connectorId: "scl_linear",
        userId: "user_1",
        name: "issue.created",
        status: "needs_auth",
        statusReason: "reauthorize",
      })
      .orThrow();

    const listed = await store
      .listByTenant("org_1", { status: "failed" })
      .orThrow();

    await store.listByTenant("org_1").orThrow();
    expect(await store.setStatus("sub_2", "stopped", "done").orThrow()).toBe(
      true,
    );
    expect(await store.remove("sub_2").orThrow()).toBe(true);

    expect(listed).toEqual([
      {
        id: "sub_2",
        tenantId: "org_1",
        connectorId: "scl_linear",
        name: "issue.created",
        status: "failed",
        statusReason: "token revoked",
        expiresAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      },
    ]);
    expect(calls.every((call) => call.text.includes('"connect"."subs"'))).toBe(
      true,
    );
    expect(calls.map((call) => call.params)).toEqual([
      [
        "sub_1",
        "org_1",
        "scl_linear",
        null,
        "issue.created",
        "active",
        null,
        new Date("2026-11-01T00:00:00Z"),
      ],
      [
        "sub_1",
        "org_1",
        "scl_linear",
        "user_1",
        "issue.created",
        "needs_auth",
        "reauthorize",
        null,
      ],
      ["org_1", "failed"],
      ["org_1", null],
      ["sub_2", "stopped", "done"],
      ["sub_2"],
    ]);
  });

  it("keeps a database error the query raised", async () => {
    const store = postgresConnectEventSubscriptions({
      queryRaw: () => Promise.reject(dbError("conflict", "taken")),
    });

    const result = await store.get("sub_1");

    expect(!result.ok && result.error.kind).toBe("conflict");
  });

  it("refuses a table name that is not an identifier", () => {
    expect(() =>
      postgresConnectEventSubscriptions(sqlFake([]).sql, { table: 'x"; drop' }),
    ).toThrow(/identifier/);
  });
});
