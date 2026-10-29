import { describe, expectTypeOf, it } from "vitest";

import type { BetterSupabase } from "../../src/core/define.ts";
import type { LiteStack } from "../../src/testing/lite.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { asUser } from "../../src/testing/as-user.ts";
import { expectTenantIsolation } from "../../src/testing/isolation.ts";
import { scopedSeed, withRollback } from "../../src/testing/scope.ts";
import { defineSeed, defineTenantSeed } from "../../src/testing/seed.ts";
import { schema } from "../fixtures/generated-camel.ts";

const base = defineSupabase(schema);

interface ScoringClient {
  readonly count: () => Promise<number>;
}

type WithBlocks<T, B> =
  T extends BetterSupabase<infer M, infer D, infer F, infer E>
    ? BetterSupabase<M, D, F, E, unknown, unknown, B>
    : never;

declare const betterSupabase: WithBlocks<
  typeof base,
  { readonly blocks: { readonly leadScoring: ScoringClient } }
>;

declare const lite: LiteStack;

const customer = { organizationId: "o1", name: "Acme" };

describe("test users of a definition with blocks", () => {
  it("types db.$blocks and each instance on asUser's db and sql", async () => {
    const alice = await asUser(betterSupabase, { sub: "u1" });

    expectTypeOf(alice.db.$blocks.leadScoring).toEqualTypeOf<ScoringClient>();
    expectTypeOf(alice.db.leadScoring).toEqualTypeOf<ScoringClient>();
    expectTypeOf(alice.sql?.$blocks.leadScoring).toEqualTypeOf<
      ScoringClient | undefined
    >();
  });

  it("keeps the blocks through liteStack and withRollback", async () => {
    const bob = await lite.asUser(betterSupabase, { sub: "u2" });

    expectTypeOf(bob.db.$blocks.leadScoring).toEqualTypeOf<ScoringClient>();

    await withRollback(bob, async (db) => {
      expectTypeOf(db.$blocks.leadScoring).toEqualTypeOf<ScoringClient>();
    });
  });

  it("accepts the definition in the seed and isolation helpers", async () => {
    defineSeed(betterSupabase, { customers: { acme: customer } });
    defineTenantSeed(betterSupabase, () => ({ customers: { acme: customer } }));
    await scopedSeed(betterSupabase, () => ({ customers: { acme: customer } }));
    await expectTenantIsolation(betterSupabase, {
      tenants: [
        { id: "t1", claims: { sub: "u1" } },
        { id: "t2", claims: { sub: "u2" } },
      ],
      tables: {},
    });
  });
});
