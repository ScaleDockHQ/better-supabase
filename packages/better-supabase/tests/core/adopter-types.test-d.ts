import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { OrderByOf } from "../fixtures/generated-camel.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { schema as camel } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
declare const flag: boolean;
const db = defineSupabase(camel).connect(client);

describe("input built conditionally", () => {
  it("accepts a mutable insert and patch", () => {
    const patch: Parameters<typeof db.customers.update>[1] = {};

    if (flag) {
      patch.name = "Acme";
    }

    void db.customers.update("c1", patch);

    const data = flag ? { name: "Acme" } : {};
    void db.customers.update("c1", data);
    void db.customers.update({ where: { status: "lead" } }, data);
    void db.customers.update({ where: { status: "lead" } }, patch);
  });
});

describe("array and object values in input", () => {
  it("accepts a literal array in updateMany data", () => {
    void db.notes.update(
      { where: { kind: "call" } },
      { attachments: [{ path: "a" }, 2] },
    );

    void db.notes.update(
      { where: { kind: "call" } },
      { attachments: ["a", "b"] },
      { returning: true },
    );
  });
});

describe("orderBy from a ternary", () => {
  it("accepts a ternary inline and a typed variable", () => {
    void db.customers.list({
      orderBy: flag ? { name: "asc" } : { createdAt: "desc" },
    });

    const orderBy: OrderByOf<"customers"> = flag
      ? { name: "asc" }
      : { createdAt: "desc" };

    void db.customers.list({ orderBy });

    const sort = flag ? "asc" : "desc";
    void db.customers.list({ orderBy: { name: sort } });

    // Normalized ternary: the other branch's key becomes `?: undefined`.
    const merged = flag
      ? { name: "asc" as const }
      : { createdAt: "desc" as const };

    void db.customers.list({ orderBy: merged });
    void db.customers.list({ orderBy: [merged] });
    void db.customers.list({ orderBy: { name: flag ? "asc" : undefined } });

    expectTypeOf(orderBy).toExtend<OrderByOf<"customers">>();
  });
});

describe("rows read back feed writes", () => {
  it("accepts a selected payload as a patch and a built insert list", async () => {
    const found = await db.notes
      .list({ select: ["attachments"], limit: 1 })
      .map((rows) => rows[0] ?? null)
      .orThrow();

    if (found) {
      void db.notes.update({ where: { kind: "call" } }, found);
      void db.notes.update({ where: { kind: "call" } }, { ...found });
    }

    const inserts: Parameters<typeof db.customers.create>[0][number][] = [];

    if (flag) {
      inserts.push({ organizationId: "o", name: "a", primaryContactId: null });
    }

    void db.customers.create(inserts);
    void db.customers.upsert(inserts);
  });
});

describe("page counts", () => {
  it("narrows total when a count is requested", async () => {
    const plain = await db.customers.page({ size: 10 }).orThrow();
    expectTypeOf(plain.page.total).toEqualTypeOf<number | null>();

    const counted = await db.customers
      .page({ size: 10, withCount: true })
      .orThrow();

    expectTypeOf(counted.page.total).toEqualTypeOf<number>();
    expectTypeOf(counted.page.pages).toEqualTypeOf<number>();

    const exact = await db.customers
      .page({ size: 10, count: "exact" })
      .orThrow();

    expectTypeOf(exact.page.total).toEqualTypeOf<number>();

    const cursor = await db.customers
      .page({ size: 10, after: null, withCount: true })
      .orThrow();

    expectTypeOf(cursor.total).toEqualTypeOf<number>();

    const bare = await db.customers.page({ size: 10, after: null }).orThrow();

    // @ts-expect-error a cursor page has no total without withCount
    void bare.total;
  });
});

describe("returning on many-row writes", () => {
  const rows = [{ organizationId: "o", name: "a", primaryContactId: null }];

  type Count = { count: number };

  it("types createMany and upsertMany by returning", async () => {
    const created = await db.customers
      .create(rows, { select: ["id"] })
      .orThrow();

    expectTypeOf(created).toEqualTypeOf<{ id: string }[]>();

    const explicit = await db.customers
      .create(rows, { returning: true, select: ["id"] })
      .orThrow();

    expectTypeOf(explicit).toEqualTypeOf<{ id: string }[]>();

    const none = await db.customers
      .create(rows, { returning: false })
      .orThrow();

    expectTypeOf(none).toEqualTypeOf<Count>();

    const wide = await db.customers
      .upsert(rows, { returning: flag, select: ["id"] })
      .orThrow();

    expectTypeOf(wide).toEqualTypeOf<{ id: string }[] | Count>();

    const upsertNone = await db.customers
      .upsert(rows, { returning: false })
      .orThrow();

    expectTypeOf(upsertNone).toEqualTypeOf<Count>();
  });

  it("types updateMany and deleteMany by returning", async () => {
    const where = { status: "lead" } as const;

    const absent = await db.customers
      .update({ where }, { name: "x" })
      .orThrow();

    expectTypeOf(absent).toEqualTypeOf<Count>();

    const off = await db.customers
      .update({ where }, { name: "x" }, { returning: false })
      .orThrow();

    expectTypeOf(off).toEqualTypeOf<Count>();

    const on = await db.customers
      .update({ where }, { name: "x" }, { returning: true, select: ["id"] })
      .orThrow();

    expectTypeOf(on).toEqualTypeOf<{ id: string }[]>();

    const wide = await db.customers
      .delete({ where }, { returning: flag, select: ["id"] })
      .orThrow();

    expectTypeOf(wide).toEqualTypeOf<{ id: string }[] | Count>();

    const deleted = await db.customers.delete({ where }).orThrow();
    expectTypeOf(deleted).toEqualTypeOf<Count>();
  });
});
