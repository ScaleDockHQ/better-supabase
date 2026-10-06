import { describe, expect, it } from "vitest";

import type { CloudEvent } from "../../../src/events/index.ts";
import type { SqlClient } from "../../../src/postgres/executor.ts";

import {
  createOutbox,
  outboxCloudEvent,
  type OutboxEvent,
} from "../../../src/blocks/outbox/outbox.ts";

interface Call {
  readonly fn: string;
  readonly args: unknown[];
}

function row(position: number, type = "organization.created") {
  return {
    position,
    id: position,
    type,
    payload: { n: position },
    source: "better-supabase/blocks/organizations",
    subject: `organizations/${String(position)}`,
    tenant: "t1",
    key: null,
    actor_id: "u1",
    created_at: "2026-01-01T00:00:00Z",
  };
}

function fakeSql(replies: Record<string, unknown[]>): {
  sql: SqlClient;
  calls: Call[];
} {
  const calls: Call[] = [];
  const sql: SqlClient = {
    async queryRaw<T>(text: string, params: unknown[] = []): Promise<T[]> {
      const fn = /\."([a-z_]+)"\(/.exec(text)?.[1] ?? "";
      calls.push({ fn, args: params });
      const queue = replies[fn];
      const value = queue && queue.length > 0 ? queue.shift() : null;
      if (value instanceof Error) throw value;
      return [{ value }] as T[];
    },
  };
  return { sql, calls };
}

const OPTIONS = { source: "https://crm.example.com" };

describe("createOutbox", () => {
  it("emits with the module's argument order", async () => {
    const { sql, calls } = fakeSql({
      emit_event: ["0199a7c4-0000-7000-8000-000000000007"],
    });
    const outbox = createOutbox(sql, { ...OPTIONS, schema: "app" });
    const result = await outbox.emit(
      "invoice.paid",
      { id: 1 },
      {
        tenant: "t1",
        key: "inv-1",
      },
    );
    expect(result).toMatchObject({
      ok: true,
      data: "0199a7c4-0000-7000-8000-000000000007",
    });
    expect(calls[0]).toEqual({
      fn: "emit_event",
      args: ["invoice.paid", '{"id":1}', null, "t1", "inv-1", null],
    });
  });

  it("registers a consumer and maps database errors", async () => {
    const failure = Object.assign(new Error("Unknown"), {
      code: "P0002",
      hint: "OUTBOX_UNKNOWN_CONSUMER",
    });
    const { sql, calls } = fakeSql({
      outbox_register: [0],
      outbox_unregister: [true],
      purge_outbox: [failure, 3],
    });
    const outbox = createOutbox(sql, OPTIONS);
    expect(
      await outbox.register("billing", {
        types: ["invoice.*"],
        fromStart: true,
      }),
    ).toMatchObject({ ok: true, data: 0 });
    expect(calls[0]!.args).toEqual(["billing", ["invoice.*"], true]);
    const purged = await outbox.purge("7 days");
    expect(purged.ok).toBe(false);
    expect(purged.error).toMatchObject({ hint: "OUTBOX_UNKNOWN_CONSUMER" });
    expect((await outbox.purge(undefined, 500)).data).toBe(3);
    expect(calls.at(-1)).toEqual({ fn: "purge_outbox", args: [null, 500] });
    expect((await outbox.unregister("billing")).data).toBe(true);
  });

  it("relays batches as CloudEvents and moves the cursor", async () => {
    const { sql, calls } = fakeSql({
      outbox_claim: [[row(1), row(2)], [row(3)]],
      outbox_ack: [true, true],
    });
    const sent: CloudEvent[] = [];
    const outbox = createOutbox(sql, { ...OPTIONS, typePrefix: "com.crm" });
    const result = await outbox.relay(
      "crm",
      { send: (events) => void sent.push(...events) },
      { batch: 2, owner: "w1" },
    );
    expect(result).toEqual({ delivered: 3 });
    expect(sent.map((event) => event.id)).toEqual(["1", "2", "3"]);
    expect(sent[0]).toMatchObject({
      type: "com.crm.organization.created",
      source: "https://crm.example.com",
      subject: "organizations/1",
      partitionkey: "t1",
      producer: "better-supabase/blocks/organizations",
      data: { n: 1 },
    });
    expect(
      calls.filter((call) => call.fn === "outbox_ack").map((call) => call.args),
    ).toEqual([
      ["crm", "w1", 2],
      ["crm", "w1", 3],
    ]);
  });

  it("hands consume handlers the rows with the actor", async () => {
    const { sql, calls } = fakeSql({
      outbox_claim: [[row(1)], [row(2)]],
      outbox_ack: [true, true, true],
    });
    const seen: OutboxEvent[] = [];
    const outbox = createOutbox(sql, OPTIONS);
    const result = await outbox.consume(
      "search",
      async (events) => {
        seen.push(...events);
      },
      { owner: "w1" },
    );
    expect(result).toEqual({ delivered: 1 });
    expect(seen[0]).toMatchObject({
      position: 1,
      type: "organization.created",
      actorId: "u1",
      tenant: "t1",
    });
    expect(calls.find((call) => call.fn === "outbox_ack")!.args).toEqual([
      "search",
      "w1",
      1,
    ]);
    const failed = await outbox.consume(
      "search",
      () => {
        throw new Error("index down");
      },
      { owner: "w1" },
    );
    expect(failed.error?.message).toContain("index down");
  });

  it("releases the lease without moving the cursor when the sink throws", async () => {
    const { sql, calls } = fakeSql({ outbox_claim: [[row(1)]] });
    const outbox = createOutbox(sql, OPTIONS);
    const result = await outbox.relay(
      "crm",
      {
        send: () => {
          throw new Error("receiver down");
        },
      },
      { owner: "w1" },
    );
    expect(result.delivered).toBe(0);
    expect(result.error?.message).toContain("receiver down");
    expect(calls.at(-1)).toEqual({
      fn: "outbox_ack",
      args: ["crm", "w1", null],
    });
  });

  it("returns the claim error", async () => {
    const { sql } = fakeSql({
      outbox_claim: [
        Object.assign(new Error("gone"), {
          code: "P0002",
          hint: "OUTBOX_UNKNOWN_CONSUMER",
        }),
      ],
    });
    const result = await createOutbox(sql, OPTIONS).relay("crm", {
      send: () => undefined,
    });
    expect(result.error).toMatchObject({ hint: "OUTBOX_UNKNOWN_CONSUMER" });
  });

  it("reads history", async () => {
    const { sql, calls } = fakeSql({ outbox_history: [[row(4), { bad: 1 }]] });
    const result = await createOutbox(sql, OPTIONS).history({
      subject: "organizations/4",
    });
    expect(result.data?.map((event) => event.position)).toEqual([4]);
    expect(result.data?.[0]?.createdAt.toString()).toBe("2026-01-01T00:00:00Z");
    expect(calls[0]!.args).toEqual(["organizations/4", null, 0, 100]);
  });

  it("builds a CloudEvent without optional fields", () => {
    const event = outboxCloudEvent(
      {
        position: 1,
        id: "1",
        type: "x",
        payload: null,
        source: null,
        subject: null,
        tenant: null,
        key: null,
        actorId: null,
        createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      },
      OPTIONS,
    );
    expect(Object.keys(event).sort()).toEqual([
      "data",
      "datacontenttype",
      "id",
      "source",
      "specversion",
      "time",
      "type",
    ]);
    expect(event.type).toBe("dev.better-supabase.x");
    expect(event.data).toBeNull();
  });

  it("keeps the payload as it is and sends no actor", () => {
    const base = {
      position: 1,
      id: "1",
      type: "x",
      source: null,
      subject: null,
      tenant: null,
      key: null,
      actorId: "u1",
      createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
    };
    const event = outboxCloudEvent({ ...base, payload: { n: 1 } }, OPTIONS);
    expect(event.data).toEqual({ n: 1 });
    expect(event).not.toHaveProperty("actorid");
  });
});

describe("relayRoute", () => {
  const request = (method = "GET", secret = "s") =>
    new Request("https://app.test/api/outbox", {
      method,
      headers: { authorization: `Bearer ${secret}` },
    });

  it("needs a secret", () => {
    const { sql } = fakeSql({});
    expect(() =>
      createOutbox(sql, OPTIONS).relayRoute({
        secret: undefined,
        consumers: {},
      }),
    ).toThrow(/secret/);
  });

  it("checks the method and the bearer secret", async () => {
    const { sql } = fakeSql({});
    const route = createOutbox(sql, OPTIONS).relayRoute({
      secret: "s",
      consumers: {},
    });
    expect((await route(request("PUT"))).status).toBe(405);
    expect((await route(request("GET", "wrong"))).status).toBe(401);
  });

  it("relays each consumer and reports sink errors", async () => {
    const { sql } = fakeSql({
      outbox_claim: [[row(1)], [row(3)], [row(2)]],
      outbox_ack: [true, true, true],
    });
    const errors: string[] = [];
    const actors: (string | null)[] = [];
    const route = createOutbox(sql, OPTIONS).relayRoute({
      secret: "s",
      consumers: {
        good: { send: () => undefined },
        rows: (events) => {
          actors.push(...events.map((event) => event.actorId));
        },
        bad: {
          send: () => {
            throw new Error("down");
          },
        },
      },
      onError: (_, consumer) => errors.push(consumer),
    });
    const response = await route(request("POST"));
    const body = await response.json();
    expect(body).toMatchObject({
      consumers: {
        good: { delivered: 1 },
        rows: { delivered: 1 },
        bad: { delivered: 0 },
      },
      budgetExhausted: false,
    });
    expect(errors).toEqual(["bad"]);
    expect(actors).toEqual(["u1"]);
  });
});
