import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { DbError } from "../../src/core/errors.ts";
import type { Result } from "../../src/core/result.ts";
import type { InferResult } from "../../src/core/spec.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { isCheck, isConflict } from "../../src/core/errors.ts";
import { rules } from "../../src/plugins/rules/index.ts";
import {
  schema as camel,
  type CheckConstraint,
  type ForeignKeyConstraint,
  type UniqueConstraint,
  type CustomersStatus,
  type TagsColor,
  type NoteKind,
  type OrderByOf,
  type OrderTermOf,
  type WhereOf,
} from "../fixtures/generated-camel.ts";
import { schema as snake } from "../fixtures/generated.ts";

declare const client: SupabaseClient;
const db = defineSupabase(camel).connect(client);
const snakeDb = defineSupabase(snake).connect(client);

describe("payload inference", () => {
  it("returns an offset page for an offset and limit window", async () => {
    const page = await db.customers
      .paginate({ select: ["id"], offset: 40, limit: 20, count: "exact" })
      .orThrow();
    expectTypeOf(page.items).toEqualTypeOf<{ id: string }[]>();
    expectTypeOf(page.page.total).toEqualTypeOf<number | null>();
    // @ts-expect-error an offset window takes limit, not size
    void db.customers.paginate({ offset: 0, limit: 10, size: 10 });
  });

  it("narrows rows to the selected columns", async () => {
    const rows = await db.customers
      .findMany({ select: ["id", "status"] })
      .orThrow();
    expectTypeOf(rows).toEqualTypeOf<
      { id: string; status: CustomersStatus }[]
    >();
  });

  it("returns full rows without a select", async () => {
    const row = await db.customers.findById("x").orThrow();
    expectTypeOf(row.organizationId).toEqualTypeOf<string>();
    expectTypeOf(row.kvk).toEqualTypeOf<string | null>();
    expectTypeOf(row.metadata).toEqualTypeOf<{
      source?: string;
      tier?: "free" | "pro";
    }>();
  });

  it("keeps database names in snake mode", async () => {
    const row = await snakeDb.customers
      .findById("x", { select: ["organization_id"] })
      .orThrow();
    expectTypeOf(row).toEqualTypeOf<{ organization_id: string }>();
  });

  it("types findOnly like findFirst and requires where", async () => {
    const row = await db.customers
      .findOnly({ where: { status: "active" }, select: ["id"] })
      .orThrow();
    expectTypeOf(row).toEqualTypeOf<{ id: string } | null>();
    // @ts-expect-error where is required
    void db.customers.findOnly({ select: ["id"] });
  });

  it("types includes by relation cardinality", async () => {
    const row = await db.customers
      .findFirst({
        select: ["id"],
        include: {
          organization: { select: ["slug"] },
          primaryContact: { select: ["email"] },
          notes: { select: ["kind"] },
          customerTags: {
            select: ["tagId"],
            include: { tag: { select: ["name"] } },
          },
        },
      })
      .orThrow();
    expectTypeOf(row).toEqualTypeOf<{
      id: string;
      organization: { slug: string };
      primaryContact: { email: string } | null;
      notes: { kind: NoteKind }[];
      customerTags: { tagId: string; tag: { name: string } }[];
    } | null>();
  });

  it("returns a Result that carries a DbError", () => {
    const pending = db.tags.create({ organizationId: "o", name: "n" });
    expectTypeOf(pending).resolves.toEqualTypeOf<
      Result<{
        id: string;
        organizationId: string;
        name: string;
        color: TagsColor;
        createdAt: string;
        updatedAt: string;
      }>
    >();
  });
});

describe("MutableWhere and WhereOf", () => {
  it("builds a filter one key at a time", () => {
    const filter = (status?: CustomersStatus, search?: string) => {
      const where: WhereOf<"customers"> = {};
      if (status) where.status = { in: [status] };
      if (search) where.OR = [{ kvk: null }, { name: { ilike: search } }];
      // @ts-expect-error status only takes its CHECK values
      if (!status) where.status = "gone";
      return db.customers.findMany({ where });
    };
    void filter;
  });
});

describe("OrderByOf", () => {
  it("types a sort built outside the call", () => {
    const sort = (newest: boolean): OrderByOf<"customers"> =>
      newest ? [{ createdAt: "desc" }, { name: "asc" }] : { name: "asc" };
    void db.customers.findMany({ orderBy: sort(true) });
    // @ts-expect-error not a column of customers
    const wrong: OrderByOf<"customers"> = { nope: "asc" };
    void wrong;
  });

  it("names one sort term with OrderTermOf", () => {
    const tiebreak: OrderTermOf<"customers"> = { id: "asc" };
    const byName: OrderTermOf<"customers"> = { name: "asc" };
    const orderBy: OrderByOf<"customers"> = [byName, tiebreak];
    void db.customers.findMany({ orderBy });
    void db.customers.findMany({ orderBy: tiebreak });
    expectTypeOf<OrderTermOf<"customers">>().toEqualTypeOf<
      Exclude<OrderByOf<"customers">, readonly unknown[]>
    >();
    // @ts-expect-error a list is not one term
    const list: OrderTermOf<"customers"> = [{ name: "asc" }];
    // @ts-expect-error not a column of customers
    const wrong: OrderTermOf<"customers"> = { nope: "asc" };
    void list;
    void wrong;
  });
});

describe("required includes", () => {
  it("drops null from a nullable to-one include with required: true", async () => {
    const rows = await db.customers
      .findMany({
        select: ["id"],
        include: {
          primaryContact: { select: ["id"], required: true },
          organization: { select: ["name"] },
        },
      })
      .orThrow();
    expectTypeOf(rows[0]!.primaryContact).toEqualTypeOf<{ id: string }>();
    const optional = await db.customers
      .findMany({ include: { primaryContact: { select: ["id"] } } })
      .orThrow();
    expectTypeOf(optional[0]!.primaryContact).toEqualTypeOf<{
      id: string;
    } | null>();
  });
});

describe("$rpc results", () => {
  it("types table rows and records in the configured casing", async () => {
    const rows = await db
      .$rpc("customers_by_status", { p_status: "lead" })
      .orThrow();
    expectTypeOf(rows[0]!.organizationId).toEqualTypeOf<string>();
    const counts = await db.$rpc("customer_note_counts").orThrow();
    expectTypeOf(counts).toEqualTypeOf<
      {
        customerId: string | null;
        lastNoteAt: string | null;
        noteCount: number | null;
      }[]
    >();
    const raw = await db
      .$rpc("customer_note_counts", {}, { raw: true })
      .orThrow();
    expectTypeOf(raw).toEqualTypeOf<unknown>();
  });
});

describe("conditional writes", () => {
  it("returns rows from updateMany and deleteMany only with returning: true", async () => {
    const counted = await db.customers
      .updateMany({ where: { status: "lead" }, data: { status: "active" } })
      .orThrow();
    expectTypeOf(counted).toEqualTypeOf<{ count: number }>();
    const updated = await db.customers
      .updateMany({
        where: { status: "lead" },
        data: { status: "active" },
        returning: true,
        select: ["id", "status"],
      })
      .orThrow();
    expectTypeOf(updated).toEqualTypeOf<
      { id: string; status: CustomersStatus }[]
    >();
    const deleted = await db.customers
      .deleteMany({ where: { status: "archived" }, returning: true })
      .orThrow();
    expectTypeOf(deleted[0]!.organizationId).toEqualTypeOf<string>();
  });

  it("sorts by to-one relations", () => {
    void db.notes.findMany({
      orderBy: [{ customer: { name: "asc" } }, { createdAt: "desc" }],
    });
    void db.notes.findMany({
      include: { customer: { select: ["name"] } },
      orderBy: { customer: { name: { direction: "desc", nulls: "last" } } },
    });
  });

  it("types json path filters", () => {
    void db.notes.findMany({
      where: {
        attachments: { path: ["owner", "id"], eq: "u1", ilike: "u%" },
        AND: [{ attachments: { path: ["kind"], in: ["a", 1] } }],
      },
    });
    void db.customers.findMany({
      where: { metadata: { path: ["tier"], eq: "pro" } },
    });
  });

  it("takes where and expect operators on update", () => {
    void db.customers.update(
      "c",
      { name: "A" },
      {
        where: { organizationId: "t", status: { in: ["lead", "active"] } },
        expect: { updatedAt: { lte: "2026-01-01T00:00:00Z" } },
      },
    );
    // @ts-expect-error status only takes its CHECK values
    void db.customers.update("c", { name: "A" }, { where: { status: "gone" } });
  });
});

describe("argument checking", () => {
  it("rejects unknown columns and relations", () => {
    // @ts-expect-error unknown column
    db.customers.findMany({ select: ["nope"] });
    // @ts-expect-error unknown filter column
    db.customers.findMany({ where: { nope: 1 } });
    // @ts-expect-error snake name in camel mode
    db.customers.findMany({ where: { organization_id: "x" } });
    // @ts-expect-error unknown relation
    db.customers.findMany({ include: { invoices: true } });
  });

  it("checks filter values against column types", () => {
    db.customers.findMany({ where: { status: { in: ["lead", "active"] } } });
    // @ts-expect-error value outside the CHECK union
    db.customers.findMany({ where: { status: "deleted" } });
    // @ts-expect-error contains is only for text
    db.notes.findMany({ where: { id: { contains: "1" } } });
    db.notes.findMany({ where: { kind: { notIn: ["email"] } } });
  });

  it("offers quantifiers only on to-many relations", () => {
    db.customers.findMany({ where: { notes: { some: { kind: "call" } } } });
    db.customers.findMany({
      where: { organization: { is: { slug: "acme" } } },
    });
    // @ts-expect-error to-one relations have no quantifiers
    db.customers.findMany({ where: { organization: { some: {} } } });
  });

  it("requires insert columns and forbids generated identities", () => {
    // @ts-expect-error name is required
    db.customers.create({ organizationId: "o" });
    // @ts-expect-error identity columns cannot be written
    db.notes.create({ id: 1, organizationId: "o", customerId: "c", body: "b" });
  });

  it("types composite primary keys", () => {
    db.customerTags.findById({ customerId: "c", tagId: "t" });
    // @ts-expect-error composite keys need every column
    db.customerTags.findById({ customerId: "c" });
  });

  it("types findUnique by the primary key or a named unique key", async () => {
    const row = await db.customers
      .findUnique({ where: { organizationId: "o", kvk: "1" }, select: ["id"] })
      .orThrow();
    expectTypeOf(row).toEqualTypeOf<{ id: string } | null>();
    db.customers.findUnique({ where: { id: "c" } });
    // @ts-expect-error a unique key needs all of its columns
    db.customers.findUnique({ where: { kvk: "1" } });
  });

  it("types constraint names", () => {
    expectTypeOf<UniqueConstraint>().toExtend<string>();
    expectTypeOf<"customers_status_check">().toExtend<CheckConstraint>();
    expectTypeOf<"customers_organization_id_fkey">().toExtend<ForeignKeyConstraint>();
    const error = {} as DbError;
    if (
      isConflict<UniqueConstraint>(error, "customers_organization_id_kvk_key")
    ) {
      expectTypeOf(error.constraint).toEqualTypeOf<UniqueConstraint>();
    }
    // @ts-expect-error unknown constraint name
    isCheck<CheckConstraint>(error, "nope");
  });

  it("types QuerySpec results like the repository", async () => {
    const betterSupabase = defineSupabase(camel);
    const spec = betterSupabase.spec.customers.findMany({
      select: ["id", "status"],
    });
    expectTypeOf<InferResult<typeof spec>>().toEqualTypeOf<
      { id: string; status: CustomersStatus }[]
    >();
    const rows = await db.$run(spec).orThrow();
    expectTypeOf(rows).toEqualTypeOf<
      { id: string; status: CustomersStatus }[]
    >();
    const page = betterSupabase.spec.customers.paginate({
      size: 10,
      after: null,
    });
    expectTypeOf<InferResult<typeof page>["nextCursor"]>().toEqualTypeOf<
      string | null
    >();
    betterSupabase.spec.customers.findMany({
      // @ts-expect-error specs never carry a signal
      signal: new AbortController().signal,
    });
  });
});

describe("_count, $table and $withoutPlugins", () => {
  it("adds _count for to-many relations only", async () => {
    const rows = await db.customers
      .findMany({
        select: ["id"],
        include: {
          _count: { notes: true, locations: { where: { city: "x" } } },
        },
      })
      .orThrow();
    expectTypeOf(rows[0]!._count).toEqualTypeOf<{
      notes: number;
      locations: number;
    }>();
    // @ts-expect-error organization is a to-one relation
    void db.customers.findMany({ include: { _count: { organization: true } } });
  });

  it("types runtime table lookups and the plugin-free connection", () => {
    expectTypeOf(db.$table("tags")).toEqualTypeOf(db.tags);
    // @ts-expect-error unknown table
    void db.$table("nope");
    expectTypeOf(db.$withoutPlugins().tags).toHaveProperty("findMany");
    expectTypeOf(db.$withoutPlugins({ keep: ["otel"] }).tags).toHaveProperty(
      "findMany",
    );
  });

  it("accepts the rules sensitive opt-in", () => {
    const ruled = defineSupabase(camel).use(rules()).connect(client);
    void ruled.contacts.findMany({ limit: 1, sensitive: true });
  });
});
