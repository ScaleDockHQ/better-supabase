import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { asUser } from "../../src/testing/as-user.ts";
import { scopedSeed, withRollback } from "../../src/testing/scope.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

describe("withRollback", () => {
  it("explains that it needs a user with postgres", async () => {
    const user = await asUser(
      betterSupabase,
      { sub: "11111111-1111-4111-8111-111111111111" },
      { publishableKey: "sb_publishable_test", alg: "HS256" },
    );

    await expect(withRollback(user, () => Promise.resolve(1))).rejects.toThrow(
      /asUser\(betterSupabase, claims, \{ postgres \}\)/,
    );
  });
});

describe("scopedSeed", () => {
  it("needs a service-role key", async () => {
    const saved = process.env["SUPABASE_SECRET_KEY"];
    delete process.env["SUPABASE_SECRET_KEY"];

    try {
      await expect(
        scopedSeed(betterSupabase, () => ({}), { stack: {} }),
      ).rejects.toThrow(/SUPABASE_SECRET_KEY/);
    } finally {
      if (saved !== undefined) {
        process.env["SUPABASE_SECRET_KEY"] = saved;
      }
    }
  });
});
