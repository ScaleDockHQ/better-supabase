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
} from "../fixtures/generated-camel.ts";
import { schema as snake } from "../fixtures/generated.ts";

declare const client: SupabaseClient;
const db = defineSupabase(camel).connect(client);
const snakeDb = defineSupabase(snake).connect(client);

describe("payload inference", () => {
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
  });

  it("accepts the rules sensitive opt-in", () => {
    const ruled = defineSupabase(camel).use(rules()).connect(client);
    void ruled.contacts.findMany({ limit: 1, sensitive: true });
  });
});
