import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { RECIPES } from "./recipes.ts";
import { dbUrl, moduleFiles, reachable, withRecipe } from "./stack.ts";

const live = await reachable();

describe("recipe module sets", () => {
  it.each(RECIPES)("$name renders the modules it names", (recipe) => {
    const rendered = new Set(moduleFiles(recipe).map((file) => file.module));
    const named = Object.keys(recipe.config.blocks ?? {});
    expect([...rendered]).toEqual(expect.arrayContaining(named));
    expect(rendered).toContain("outbox");
  });
});

describe.skipIf(!live)("installing a recipe", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  afterAll(() => pool.end());

  it.each(RECIPES)(
    "$name applies as one migration",
    async (recipe) => {
      await withRecipe(pool, recipe, async (s) => {
        expect(
          await s.value<boolean>(
            "to_regprocedure('better_supabase.emit_event(text, jsonb, text, text, text, text)') is not null",
          ),
        ).toBe(true);
      });
    },
    30_000,
  );
});
