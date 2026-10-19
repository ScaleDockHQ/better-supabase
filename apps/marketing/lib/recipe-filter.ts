// Kept apart from `recipes.ts`, which loads the recipe and catalog JSON, so
// the client filters can import it.

import type { RecipePlatform } from "./recipe-platform";

/** A piece of UI inside a page, or a whole page. */
export type RecipeKind = "component" | "screen";

export const recipeKinds: readonly RecipeKind[] = ["component", "screen"];

/**
 * Recipe categories that no block has: recipes over the app's own tables
 * (`appTables`) group here.
 */
export const RECIPE_CATEGORY_NAMES = ["App tables"] as const;

/** The fields a recipe tile renders and the `/recipes` filters read. */
export interface RecipeSummary {
  readonly slug: string;
  readonly title: string;
  readonly description: string;
  /** The primary block, which sets the category. */
  readonly block: string;
  readonly blocks: readonly string[];
  readonly category: string;
  readonly kind: RecipeKind;
  readonly platforms: readonly RecipePlatform[];
  readonly hook: string | null;
  readonly screenshot: {
    readonly src: string;
    readonly width: number;
    readonly height: number;
  } | null;
}

export function recipePath(slug: string): `/recipes/${string}` {
  return `/recipes/${slug}`;
}

export const ALL = "all";

export interface RecipeFilter {
  readonly category: string;
  readonly platform: RecipePlatform | typeof ALL;
  readonly kind: RecipeKind | typeof ALL;
}

export const NO_FILTER: RecipeFilter = {
  category: ALL,
  platform: ALL,
  kind: ALL,
};

export function isFiltering(filter: RecipeFilter): boolean {
  return (
    filter.category !== ALL || filter.platform !== ALL || filter.kind !== ALL
  );
}

/** The recipes in the filter's category, on its platform and of its kind. */
export function filterRecipes<T extends RecipeSummary>(
  recipes: readonly T[],
  filter: RecipeFilter,
): T[] {
  return recipes.filter(
    (recipe) =>
      (filter.category === ALL || recipe.category === filter.category) &&
      (filter.platform === ALL || recipe.platforms.includes(filter.platform)) &&
      (filter.kind === ALL || recipe.kind === filter.kind),
  );
}
