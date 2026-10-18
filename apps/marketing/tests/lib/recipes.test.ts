import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

import { getBlock } from "../../lib/blocks";
import {
  availableRecipes,
  getRecipe,
  plannedRecipes,
  recipes,
  recipeStaticParams,
} from "../../lib/recipes";

const PAGE = join(
  import.meta.dirname,
  "../../app/(catalog)/recipes/[slug]/page.tsx",
);

const REGISTRY = join(
  import.meta.dirname,
  "../../../../packages/registry/registry.json",
);

describe("recipes", () => {
  test("every available recipe has a statically generated page", () => {
    expect(readFileSync(PAGE, "utf-8")).toContain(
      "return recipeStaticParams();",
    );
    expect(recipeStaticParams().map((param) => param.slug)).toEqual(
      availableRecipes.map((recipe) => recipe.slug),
    );

    for (const recipe of availableRecipes) {
      expect(getRecipe(recipe.slug)).toBe(recipe);
    }

    expect(availableRecipes.length).toBeGreaterThan(0);
    expect(plannedRecipes.length + availableRecipes.length).toBe(15);
  });

  test.each(availableRecipes.map((recipe) => [recipe.slug, recipe] as const))(
    "%s calls the same hook on the web and in React Native",
    (_slug, recipe) => {
      for (const side of [recipe.web, recipe.native]) {
        expect(side.snippet.code).toContain(`import { ${recipe.hook.name} }`);
        expect(side.snippet.code).toContain(`${recipe.hook.name}(`);
        expect(side.snippet.code).not.toContain("#region");
      }

      expect(recipe.web.snippet.code).not.toContain("react-native");
      expect(recipe.native.snippet.code).toContain('from "react-native"');
    },
  );

  test("every recipe names a catalog block, and its glue is a registry item", () => {
    const items = new Set(
      (
        JSON.parse(readFileSync(REGISTRY, "utf-8")) as {
          items: { name: string }[];
        }
      ).items.map((item) => item.name),
    );

    for (const recipe of recipes) {
      expect(getBlock(recipe.block)?.name).toBe(recipe.block);

      for (const item of [
        ...(recipe.web?.glue ?? []),
        ...(recipe.native?.glue ?? []),
      ]) {
        expect(items).toContain(item);
      }
    }
  });
});
