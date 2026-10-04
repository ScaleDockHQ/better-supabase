import { describe, expect, it, vi } from "vitest";

import type { MutationNotice } from "../../src/core/events.ts";

import { memoryCache } from "../../src/core/cache.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import {
  type CloudEvent,
  forwardMutations,
  fromHttp,
  httpSink,
  toCloudEvents,
  toHttp,
} from "../../src/events/index.ts";
import { softDelete } from "../../src/plugins/soft-delete/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const fixed = {
  id: () => "evt-1",
  now: () => Temporal.Instant.from("2026-01-01T00:00:00Z"),
  source: "/crm",
};

describe("CloudEvents", () => {
  it("builds one event per row", () => {
    const events = toCloudEvents(
      {
        table: "customers",
        kind: "insert",
        rows: [{ id: "c1", name: "Acme" }],
        context: { tenant: "org-1", actor: { id: "u1", kind: "user" } },
      },
      { ...fixed, meta: schema.meta },
    );
    expect(events).toEqual([
      {
        specversion: "1.0",
        id: "evt-1",
        source: "/crm",
        type: "dev.better-supabase.row.created",
        subject: "customers/c1",
        time: "2026-01-01T00:00:00Z",
        datacontenttype: "application/json",
        data: {
          table: "customers",
          row: { id: "c1", name: "Acme" },
          actorId: "u1",
        },
        partitionkey: "org-1",
      },
    ]);
    const custom = toCloudEvents(
      { table: "notes", kind: "delete", rows: [{}], context: {} },
      { ...fixed, typePrefix: "com.acme" },
    );
    expect(custom[0]).toMatchObject({ type: "com.acme.row.deleted" });
    expect(custom[0]).not.toHaveProperty("subject");
  });

  it("forwards mutations to a sink", async () => {
    const betterSupabase = defineSupabase(schema);
    const sent: CloudEvent[][] = [];
    const stop = forwardMutations(
      betterSupabase,
      { send: (events) => void sent.push([...events]) },
      { ...fixed, filter: (n) => n.table === "customers" },
    );
    const { client } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c9", organization_id: "o1", name: "N" }],
    }));
    const db = betterSupabase.connect(client);
    await db.customers.create({ organizationId: "o1", name: "N" }).orThrow();
    await db.notes.create({
      customerId: "c9",
      body: "x",
      kind: "call",
    } as never);
    stop();
    await db.customers.create({ organizationId: "o1", name: "M" }).orThrow();
    expect(sent).toHaveLength(1);
    expect(sent[0]?.[0]).toMatchObject({
      subject: "customers/c9",
      data: { table: "customers", row: { id: "c9" } },
    });
  });

  it("tracks sends in flight until they settle, failed ones too", async () => {
    const betterSupabase = defineSupabase(schema);
    let release: () => void = () => undefined;
    const late = new Promise<void>((resolve) => {
      release = resolve;
    });
    const delivered: string[] = [];
    const failures: unknown[] = [];
    forwardMutations(
      betterSupabase,
      {
        send: async (events) => {
          await late;
          if (events[0]?.subject === "customers/c2") throw new Error("down");
          delivered.push(String(events[0]?.subject));
        },
      },
      { ...fixed, onError: (error) => failures.push(error) },
    );
    let id = 0;
    const { client } = capturingClient(() => ({
      status: 201,
      body: [{ id: `c${String(++id)}`, organization_id: "o1", name: "N" }],
    }));
    const db = betterSupabase.connect(client);
    await db.customers.create({ organizationId: "o1", name: "N" }).orThrow();
    await db.customers.create({ organizationId: "o1", name: "N" }).orThrow();
    expect(betterSupabase.events.pending).toBe(true);
    let flushed = false;
    const flush = betterSupabase.events.settled().then(() => {
      flushed = true;
    });
    await Promise.resolve();
    expect(flushed).toBe(false);
    release();
    await flush;
    expect(delivered).toEqual(["customers/c1"]);
    expect(failures).toEqual([new Error("down")]);
    expect(betterSupabase.events.pending).toBe(false);
  });

  it("reports soft deletes by key with the resolved tenant", async () => {
    const betterSupabase = defineSupabase(schema)
      .use(softDelete())
      .use(tenant());
    const sent: CloudEvent[] = [];
    forwardMutations(
      betterSupabase,
      { send: (events) => void sent.push(...events) },
      fixed,
    );
    const cache = memoryCache();
    betterSupabase.cache(cache);
    const notices: MutationNotice[] = [];
    betterSupabase.events.on("mutation", (notice) => notices.push(notice));
    const { client } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/1" },
    }));
    await betterSupabase
      .connect(client, { claims: { tenant_id: "org-1" } })
      .customers.delete("c1")
      .orThrow();
    expect(notices[0]).toMatchObject({
      kind: "update",
      intent: "softDelete",
      rows: [],
      keys: [{ id: "c1" }],
      tenant: "org-1",
    });
    expect(sent[0]).toMatchObject({
      type: "dev.better-supabase.row.softdeleted",
      subject: "customers/c1",
      partitionkey: "org-1",
    });
    expect(cache.invalidated[0]).toMatchObject({
      table: "customers",
      ids: ["c1"],
      tenant: "org-1",
    });
  });

  it("hands hooks and listeners a copy of the rows", async () => {
    const tamper = definePlugin({
      name: "tamper",
      afterMutation(event) {
        (event.rows[0] as Record<string, unknown>)["name"] = "changed";
      },
    });
    const betterSupabase = defineSupabase(schema).use(tamper);
    betterSupabase.events.on("mutation", (notice) => {
      (notice.rows[0] as Record<string, unknown>)["id"] = "other";
    });
    const { client } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c1", name: "Acme", metadata: { tier: "pro" } }],
    }));
    const row = await betterSupabase
      .connect(client)
      .customers.create({ organizationId: "o1", name: "Acme" })
      .orThrow();
    expect(row).toMatchObject({ id: "c1", name: "Acme" });
  });

  it("reports sink failures without failing the mutation", async () => {
    const betterSupabase = defineSupabase(schema);
    const onError = vi.fn();
    forwardMutations(
      betterSupabase,
      { send: () => Promise.reject(new Error("down")) },
      { ...fixed, onError },
    );
    const { client } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c1" }],
    }));
    await betterSupabase
      .connect(client)
      .customers.create({ organizationId: "o1", name: "N" })
      .orThrow();
    await vi.waitFor(() => {
      expect(onError).toHaveBeenCalledOnce();
    });
  });

  it("round-trips the HTTP binding in every mode", async () => {
    const event: CloudEvent = {
      specversion: "1.0",
      id: "1",
      source: "/s",
      type: "t",
      subject: "a b",
      data: { x: 1 },
      datacontenttype: "application/json",
    };
    for (const mode of ["structured", "binary", "batch"] as const) {
      const [message] = toHttp([event], mode);
      const parsed = await fromHttp(
        new Request("http://x", {
          method: "POST",
          headers: message!.headers,
          body: message!.body,
        }),
      );
      expect(parsed).toEqual([event]);
    }
    expect(toHttp([event], "binary")[0]?.headers).toMatchObject({
      "ce-id": "1",
      "ce-subject": "a b",
      "content-type": "application/json",
    });
  });

  it("posts batches over HTTP", async () => {
    const fetch = vi.fn(
      async (_url: string | URL | Request, _init?: RequestInit) =>
        new Response(null, { status: 202 }),
    );
    await httpSink("http://sink", {
      fetch,
      headers: { authorization: "Bearer t" },
    }).send([{ specversion: "1.0", id: "1", source: "/s", type: "t" }]);
    expect(fetch.mock.calls[0]?.[1]).toMatchObject({
      method: "POST",
      headers: {
        authorization: "Bearer t",
        "content-type": "application/cloudevents-batch+json",
      },
    });
    const failing = httpSink("http://sink", {
      fetch: async () => new Response(null, { status: 500 }),
    });
    await expect(
      failing.send([{ specversion: "1.0", id: "1", source: "/s", type: "t" }]),
    ).rejects.toThrow("Event sink responded 500");
  });
});
