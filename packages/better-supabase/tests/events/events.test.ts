import { describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  type CloudEvent,
  forwardMutations,
  fromHttp,
  httpSink,
  toCloudEvents,
  toHttp,
} from "../../src/events/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const fixed = {
  id: () => "evt-1",
  now: () => new Date("2026-01-01T00:00:00Z"),
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
        time: "2026-01-01T00:00:00.000Z",
        datacontenttype: "application/json",
        data: { table: "customers", row: { id: "c1", name: "Acme" } },
        partitionkey: "org-1",
        actorid: "u1",
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
    const sb = defineSupabase(schema);
    const sent: CloudEvent[][] = [];
    const stop = forwardMutations(
      sb,
      { send: (events) => void sent.push([...events]) },
      { ...fixed, filter: (n) => n.table === "customers" },
    );
    const { client } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c9", organization_id: "o1", name: "N" }],
    }));
    const db = sb.connect(client);
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

  it("reports sink failures without failing the mutation", async () => {
    const sb = defineSupabase(schema);
    const onError = vi.fn();
    forwardMutations(
      sb,
      { send: () => Promise.reject(new Error("down")) },
      { ...fixed, onError },
    );
    const { client } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c1" }],
    }));
    await sb
      .connect(client)
      .customers.create({ organizationId: "o1", name: "N" })
      .orThrow();
    await vi.waitFor(() => expect(onError).toHaveBeenCalledOnce());
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
