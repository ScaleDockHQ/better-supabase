import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

import { blockCategories, getBlock } from "../../lib/blocks";
import {
  availableRecipes,
  getRecipe,
  plannedRecipes,
  recipeCategory,
  recipeGroups,
  recipePlatformsOf,
  recipes,
  recipeSide,
  recipeStaticParams,
} from "../../lib/recipes";

const PAGE = join(
  import.meta.dirname,
  "../../app/(recipes)/recipes/[slug]/page.tsx",
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
    expect(plannedRecipes.length + availableRecipes.length).toBe(
      recipes.length,
    );
    expect(new Set(recipes.map((recipe) => recipe.slug)).size).toBe(
      recipes.length,
    );
  });

  test("every planned recipe says what it waits for", () => {
    for (const recipe of plannedRecipes) {
      expect(recipe.missing).toBeTruthy();
    }
  });

  test.each(availableRecipes.map((recipe) => [recipe.slug, recipe] as const))(
    "%s has web code, and its hook is on every side",
    (_slug, recipe) => {
      const platforms = recipePlatformsOf(recipe);

      expect(platforms[0]).toBe("web");
      expect(recipe.blocks[0]).toBe(recipe.block);

      for (const platform of platforms) {
        const { code } = recipeSide(recipe, platform).snippet;

        for (const name of recipe.hook ? [recipe.hook.name] : []) {
          expect(code).toContain(`import { ${name} }`);
          expect(code).toContain(`${name}(`);
        }

        expect(code).not.toContain("#region");
      }

      expect(recipe.web.snippet.code).not.toContain("react-native");

      for (const native of recipe.native ? [recipe.native] : []) {
        expect(native.snippet.code).toContain('from "react-native"');
      }
    },
  );

  test("recipeGroups puts every recipe once under its block's category, in catalog order", () => {
    const groups = recipeGroups();

    const slugs = groups.flatMap((group) => [
      ...group.available.map((recipe) => recipe.slug),
      ...group.planned.map((recipe) => recipe.slug),
    ]);

    expect(slugs.toSorted()).toEqual(
      recipes.map((recipe) => recipe.slug).toSorted(),
    );
    expect(groups.map((group) => group.category)).toEqual(
      blockCategories.filter((category) =>
        groups.some((group) => group.category === category),
      ),
    );

    for (const group of groups) {
      expect(group.available.length + group.planned.length).toBeGreaterThan(0);

      for (const recipe of [...group.available, ...group.planned]) {
        expect(recipeCategory(recipe)).toBe(group.category);
        expect(getBlock(recipe.block)?.category).toBe(group.category);
      }

      for (const recipe of group.available) {
        expect(recipe.status).toBe("available");
      }
    }
  });

  test("every recipe names a catalog block, and its glue is a registry item", () => {
    const items = new Set(
      (
        JSON.parse(readFileSync(REGISTRY, "utf-8")) as {
          items: { name: string }[];
        }
      ).items.map((item) => item.name),
    );

    for (const recipe of recipes) {
      for (const block of recipe.blocks) {
        expect(getBlock(block)?.name).toBe(block);
      }

      for (const item of [
        ...(recipe.web?.glue ?? []),
        ...(recipe.native?.glue ?? []),
      ]) {
        expect(items).toContain(item);
      }
    }
  });
});
