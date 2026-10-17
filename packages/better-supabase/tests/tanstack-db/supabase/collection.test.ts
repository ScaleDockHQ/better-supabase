import type { StandardSchemaV1 } from "@standard-schema/spec";

import { createCollection } from "@tanstack/db";
import { QueryClient } from "@tanstack/query-core";
import { describe, expect, it } from "vitest";

import type { SchemaMeta } from "../../../src/schema/types.ts";

import { defineSupabase } from "../../../src/core/define.ts";
import { DbException } from "../../../src/core/errors.ts";
import { defineSchema } from "../../../src/schema/define.ts";
import { supabaseCollection } from "../../../src/tanstack-db/supabase/index.ts";
import { capturingClient } from "../../fixtures/client.ts";
import {
  schema as camelSchema,
  type Models as CamelModels,
} from "../../fixtures/generated-camel.ts";
import { schema, type Models } from "../../fixtures/generated.ts";

const betterSupabase = defineSupabase(schema);

interface Customer {
  readonly id: string;
  readonly name: string;
  readonly status?: string;
}

function rowSchema<T>(): StandardSchemaV1<T> {
  return {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value) => ({ value: value as T }),
    },
  };
}

const customerRow = rowSchema<Customer>();

function withTable(
  table: string,
  change: (meta: SchemaMeta["tables"][string]) => SchemaMeta["tables"][string],
) {
  const { meta } = schema;
  const tableMeta = meta.tables[table];

  if (!tableMeta) {
    throw new Error(table);
  }

  return defineSupabase(
    defineSchema<Models>({
      ...meta,
      tables: { ...meta.tables, [table]: change(tableMeta) },
    }),
  );
}

async function settle(): Promise<void> {
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });
}

describe("supabaseCollection", () => {
  it("builds on supabaseCollectionOptions with the table name and primary key", () => {
    const { client } = capturingClient();

    const config = supabaseCollection(betterSupabase, client, "customers", {
      schema: customerRow,
      db: betterSupabase.connect(client),
      realtime: false,
      realtimeUseFilter: false,
      queryClient: new QueryClient(),
    });

    expect(config.id).toBe("customers");
    expect(config.getKey({ id: "c1", name: "Acme" })).toBe("c1");
    expect(config.onInsert).toBeTypeOf("function");
  });

  it("keeps the package's own handlers with direct writes", () => {
    const { client } = capturingClient();

    const config = supabaseCollection(betterSupabase, client, "customers", {
      schema: customerRow,
      writes: "direct",
    });

    expect(config.onInsert?.name).not.toBe("onInsert");
  });

  it("reads and writes camel casing in the table's own schema", async () => {
    const { meta } = camelSchema;
    const customersMeta = meta.tables["customers"]!;

    const crm = defineSupabase(
      defineSchema<CamelModels>({
        ...meta,
        tables: {
          ...meta.tables,
          customers: { ...customersMeta, schema: "crm" },
        },
      }),
    );

    const { client, requests } = capturingClient(() => ({
      body: [{ id: "c1", name: "Acme", organization_id: "o1" }],
    }));

    const customers = createCollection(
      supabaseCollection(crm, client, "customers", {
        schema: rowSchema<{
          id: string;
          name: string;
          organizationId: string;
        }>(),
        writes: "direct",
        realtime: false,
      }),
    );

    await customers
      .insert({ id: "c1", name: "Acme", organizationId: "o1" })
      .when("settled");

    expect(requests.at(-1)).toMatchObject({
      method: "POST",
      path: "/rest/v1/customers",
      body: { id: "c1", name: "Acme", organization_id: "o1" },
    });
    expect(requests.at(-1)?.headers.get("content-profile")).toBe("crm");
    expect(customers.get("c1")).toMatchObject({ organizationId: "o1" });
  });

  it("rejects unknown tables and tables without a primary key", () => {
    const { client } = capturingClient();
    expect(() =>
      supabaseCollection(betterSupabase, client, "missing" as "customers", {
        schema: customerRow,
        writes: "direct",
      }),
    ).toThrow(/unknown table "missing"/);

    const keyless = withTable("customers", (meta) => ({
      ...meta,
      primaryKey: [],
    }));

    expect(() =>
      supabaseCollection(keyless, client, "customers", {
        schema: customerRow,
        writes: "direct",
      }),
    ).toThrow(/needs a table with a primary key/);
  });

  it("sends writes through the repository and writes the returned rows", async () => {
    const { client, requests } = capturingClient(() => ({
      body: [{ id: "c1", name: "Acme", status: "active" }],
      headers: { "content-range": "0-0/1" },
    }));

    const db = betterSupabase.connect(client);

    const customers = createCollection(
      supabaseCollection(betterSupabase, client, "customers", {
        schema: customerRow,
        db: () => db,
        realtime: false,
      }),
    );

    await customers.insert({ id: "c1", name: "Acme" }).when("settled");
    expect(requests.at(-1)).toMatchObject({
      method: "POST",
      path: "/rest/v1/customers",
      body: { id: "c1", name: "Acme" },
    });
    expect(customers.get("c1")).toMatchObject({
      id: "c1",
      name: "Acme",
      status: "active",
    });

    await customers
      .update("c1", (draft) => {
        draft.name = "Acme Inc";
      })
      .when("settled");
    expect(requests.at(-1)).toMatchObject({
      method: "PATCH",
      body: { name: "Acme Inc" },
    });
    expect(requests.at(-1)?.params.get("id")).toBe("eq.c1");

    await customers.delete("c1").when("settled");
    expect(requests.at(-1)).toMatchObject({ method: "DELETE" });
    await settle();
    expect(customers.has("c1")).toBe(false);
  });

  it("refetches instead of writing rows back for tables with codec columns", async () => {
    const withCodec = withTable("customers", (meta) => ({
      ...meta,
      columns: {
        ...meta.columns,
        created_at: { ...meta.columns["created_at"]!, codec: "instant" },
      },
    }));

    const { client } = capturingClient(() => ({
      body: [{ id: "c1", name: "Acme" }],
    }));

    const config = supabaseCollection(withCodec, client, "customers", {
      schema: customerRow,
      db: withCodec.connect(client),
    });

    const mutation = { original: {}, modified: { id: "c1" }, changes: {} };

    const params = {
      transaction: { mutations: [mutation] },
      collection: { utils: {} },
    };

    await expect(config.onInsert?.(params as never)).resolves.toEqual({
      refetch: true,
    });
    await expect(
      config.onUpdate?.({
        ...params,
        transaction: {
          mutations: [
            { ...mutation, original: { id: "c1" }, changes: { name: "B" } },
          ],
        },
      } as never),
    ).resolves.toEqual({ refetch: true });
    await expect(
      config.onDelete?.({
        ...params,
        transaction: {
          mutations: [{ ...mutation, original: { id: "c1" } }],
        },
      } as never),
    ).resolves.toEqual({ refetch: true });
    expect(mutation.modified).toEqual({ id: "c1" });
  });

  it("builds composite keys and throws DbException on a failed write", async () => {
    const { client, requests } = capturingClient(() => ({
      status: 409,
      body: {
        code: "23505",
        message: "duplicate key",
        details: null,
        hint: null,
      },
    }));

    const config = supabaseCollection(betterSupabase, client, "customer_tags", {
      schema: rowSchema<{ customer_id: string; tag_id: string }>(),
      db: betterSupabase.connect(client),
    });

    expect(config.getKey({ customer_id: "c1", tag_id: "t1" })).toBe("c1-t1");

    const params = {
      transaction: {
        mutations: [
          {
            original: { customer_id: "c1", tag_id: "t1" },
            modified: {},
            changes: {},
          },
        ],
      },
      collection: { utils: {} },
    };

    await expect(config.onDelete?.(params as never)).rejects.toBeInstanceOf(
      DbException,
    );
    expect(requests.at(-1)?.params.get("customer_id")).toBe("eq.c1");
    expect(requests.at(-1)?.params.get("tag_id")).toBe("eq.t1");
  });

  it("names the repository method when the db lacks it", async () => {
    const { client } = capturingClient();

    const config = supabaseCollection(betterSupabase, client, "customers", {
      schema: customerRow,
      db: {} as never,
    });

    await expect(
      config.onInsert?.({
        transaction: { mutations: [] },
        collection: {},
      } as never),
    ).rejects.toThrow("customers.create is not available");
  });
});
