import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it } from "vitest";

import type { TableMeta } from "../../../src/schema/types.ts";

import { tableClient } from "../../../src/tanstack-db/supabase/table-client.ts";
import { capturingClient, query } from "../../fixtures/client.ts";
import { schema as camelSchema } from "../../fixtures/generated-camel.ts";
import { schema } from "../../fixtures/generated.ts";

const customers: TableMeta = {
  ...camelSchema.meta.tables["customers"]!,
  schema: "better_supabase",
};

describe("tableClient", () => {
  it("returns the client itself for a public table with matching names", () => {
    const { client } = capturingClient();

    expect(tableClient(client, schema.meta.tables["customers"]!)).toBe(client);
  });

  it("renames filters, logic trees, order and rows", async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ id: "c1", organization_id: "o1", created_at: "now" }],
    }));

    const builder = tableClient(client, customers).from("customers");
    const url = new URL(builder.url.toString());
    url.search = new URLSearchParams([
      ["select", "*"],
      ["organizationId", "eq.o1"],
      [
        "or",
        '(createdAt.gt.2026,and(name.eq."a,b",organizationId.in.(o1,o2)))',
      ],
      ["order", "createdAt.desc,id.asc"],
      ["limit", "10"],
    ]).toString();

    // SAFETY: the builder's fetch is set; supabase-js wraps it with auth.
    const response = await builder.fetch!(url.toString(), {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ organizationId: "o2" }),
    });

    expect(query(last())).toEqual([
      "select=*",
      "organization_id=eq.o1",
      'or=(created_at.gt.2026,and(name.eq."a,b",organization_id.in.(o1,o2)))',
      "order=created_at.desc,id.asc",
      "limit=10",
    ]);
    expect(last().body).toEqual({ organization_id: "o2" });
    expect(builder.schema).toBe("better_supabase");
    await expect(response.json()).resolves.toEqual([
      { id: "c1", organizationId: "o1", createdAt: "now" },
    ]);
  });

  it("scopes Realtime listeners to the schema and renames payloads", () => {
    const listeners: {
      filter: Record<string, unknown>;
      callback: (payload: unknown) => void;
    }[] = [];

    const removed: unknown[] = [];

    const channel = {
      on(
        _type: string,
        filter: Record<string, unknown>,
        callback: (payload: unknown) => void,
      ) {
        listeners.push({ filter, callback });

        return channel;
      },
    };

    const fake = {
      channel: () => channel,
      removeChannel: (value: unknown) => {
        removed.push(value);
      },
    };

    // SAFETY: the test client implements the two methods tableClient wraps.
    const scoped = tableClient(fake as unknown as SupabaseClient, customers);
    const received: unknown[] = [];

    const wrapped = scoped
      .channel("topic")
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "customers",
          filter: 'organizationId=eq.o1,name=in.("a,b",c)',
        },
        (payload) => received.push(payload.new),
      );

    expect(listeners[0]?.filter).toEqual({
      event: "INSERT",
      schema: "better_supabase",
      table: "customers",
      filter: 'organization_id=eq.o1,name=in.("a,b",c)',
    });

    listeners[0]?.callback({ new: { organization_id: "o1" }, old: {} });
    expect(received).toEqual([{ organizationId: "o1" }]);

    void scoped.removeChannel(wrapped);
    expect(removed).toEqual([channel]);
  });

  it("passes other channel events, properties and payloads through", () => {
    const events: [string, unknown][] = [];
    let callback: (payload: unknown) => void = () => undefined;

    const channel = {
      topic: "topic",
      on(type: string, filter: unknown, listener: (payload: unknown) => void) {
        events.push([type, filter]);
        callback = listener;

        return channel;
      },
    };

    // SAFETY: the test client implements the one method this test calls.
    const fake = { channel: () => channel } as unknown as SupabaseClient;
    const scoped = tableClient(fake, customers).channel("topic");
    const received: unknown[] = [];

    expect(scoped.topic).toBe("topic");
    expect(scoped.on("broadcast", { event: "ping" }, () => undefined)).toBe(
      scoped,
    );
    scoped.on(
      "postgres_changes",
      { event: "DELETE", schema: "public", table: "customers", filter: "id" },
      (payload) => received.push(payload.old),
    );
    callback({ new: "kept", old: [{ organization_id: "o1" }] });

    expect(events).toEqual([
      ["broadcast", { event: "ping" }],
      [
        "postgres_changes",
        {
          event: "DELETE",
          schema: "better_supabase",
          table: "customers",
          filter: "id",
        },
      ],
    ]);
    expect(received).toEqual([[{ organizationId: "o1" }]]);
  });

  it("renames negated logic and escaped quotes, and leaves errors as sent", async () => {
    const { client, last } = capturingClient(() => ({
      status: 400,
      body: { message: "bad" },
    }));

    const builder = tableClient(client, customers).from("customers");
    const url = new URL(builder.url.toString());
    url.search = new URLSearchParams([
      ["not.or", '(name.eq."a\\"b",not.and(organizationId.is.null))'],
    ]).toString();

    // SAFETY: the builder's fetch is set; supabase-js wraps it with auth.
    const response = await builder.fetch!(url.toString());

    expect(query(last())).toEqual([
      'not.or=(name.eq."a\\"b",not.and(organization_id.is.null))',
    ]);
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({ message: "bad" });
  });

  it("only moves the schema when the names already match", () => {
    const { client } = capturingClient();

    const table: TableMeta = {
      ...schema.meta.tables["customers"]!,
      schema: "crm",
    };

    expect(tableClient(client, table).from("customers").schema).toBe("crm");
  });
});
