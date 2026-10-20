import { describe, expect, expectTypeOf, it } from "vitest";

import type { BucketClient } from "../../src/storage/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const logos = defineBucket({
  id: "logos",
  path: "{organizationId}/{customerId}/logo.webp",
});

const avatars = defineBucket({ id: "avatars", path: "{userId}/avatar.webp" });
const betterSupabase = defineSupabase(schema).buckets({ logos, avatars });
const storage = { from: () => ({}) } as never;

const executor = {
  name: "fake",
  execute: async () => ok({ rows: [], count: 0 }),
};

describe("db.$buckets", () => {
  it("connects each registered bucket to the storage of the db", () => {
    const db = betterSupabase.connect(executor, {}, { storage });

    expect(Object.keys(db.$buckets)).toEqual(["logos", "avatars"]);
    expect(db.$buckets.logos.bucket).toBe(logos);
    expect(db.$buckets.avatars.bucket).toBe(avatars);
  });

  it("creates the clients once per db", () => {
    const db = betterSupabase.connect(executor, {}, { storage });

    expect(db.$buckets).toBe(db.$buckets);
    // SAFETY: $with keeps the definition, so the new Db has $buckets too; its type doesn't say so.
    const scoped = db.$with({}) as typeof db;

    expect(scoped.$buckets).toBe(scoped.$buckets);
    expect(scoped.$buckets).not.toBe(db.$buckets);
  });

  it("types the clients by bucket", () => {
    const db = betterSupabase.connect(executor, {}, { storage });

    expectTypeOf(db.$buckets.logos).toEqualTypeOf<
      BucketClient<"{organizationId}/{customerId}/logo.webp", "logos">
    >();
    // @ts-expect-error not registered
    void db.$buckets.other;
    // @ts-expect-error a definition without buckets has no $buckets
    void defineSupabase(schema).connect(executor).$buckets;
  });
});
