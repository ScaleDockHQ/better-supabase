import { describe, expect, test } from "vitest";

import {
  ALL,
  filterRecipes,
  isFiltering,
  NO_FILTER,
  type RecipeSummary,
} from "../../lib/recipe-filter";

function summary(
  slug: string,
  overrides: Partial<RecipeSummary> = {},
): RecipeSummary {
  return {
    slug,
    title: slug,
    description: "",
    block: "inbox",
    blocks: ["inbox"],
    category: "Messaging",
    kind: "component",
    platforms: ["web"],
    hook: null,
    screenshot: null,
    ...overrides,
  };
}

const RECIPES = [
  summary("bell", { platforms: ["web", "native"], hook: "useNotifications" }),
  summary("settings", { kind: "screen", category: "Tenancy" }),
  summary("inbox", { kind: "screen" }),
];

describe("filterRecipes", () => {
  test("no filter keeps every recipe", () => {
    expect(isFiltering(NO_FILTER)).toBe(false);
    expect(filterRecipes(RECIPES, NO_FILTER)).toEqual(RECIPES);
  });

  test("filters by category, platform and kind together", () => {
    const slugs = (filter: typeof NO_FILTER) =>
      filterRecipes(RECIPES, filter).map((recipe) => recipe.slug);

    expect(slugs({ ...NO_FILTER, category: "Messaging" })).toEqual([
      "bell",
      "inbox",
    ]);
    expect(slugs({ ...NO_FILTER, platform: "native" })).toEqual(["bell"]);
    expect(slugs({ ...NO_FILTER, kind: "screen" })).toEqual([
      "settings",
      "inbox",
    ]);
    expect(
      slugs({ category: "Messaging", platform: ALL, kind: "screen" }),
    ).toEqual(["inbox"]);
    expect(
      slugs({ category: "Tenancy", platform: "native", kind: ALL }),
    ).toEqual([]);
    expect(isFiltering({ ...NO_FILTER, kind: "screen" })).toBe(true);
  });
});
