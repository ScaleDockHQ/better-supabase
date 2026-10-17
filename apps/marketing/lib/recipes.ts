import * as v from "valibot";

// Written by scripts/build-recipes.ts from the example apps' region markers
// before every build, dev, typecheck, lint and test run (Turbo `//#recipes`).
import recipesJson from "./recipes.json";

const side = v.nullable(
  v.object({
    file: v.string(),
    components: v.array(v.string()),
    glue: v.array(v.string()),
    snippet: v.object({ file: v.string(), code: v.string() }),
  }),
);

const recipesSchema = v.array(
  v.object({
    slug: v.string(),
    title: v.string(),
    block: v.string(),
    description: v.string(),
    status: v.picklist(["available", "planned"]),
    hook: v.nullable(v.object({ name: v.string(), entry: v.string() })),
    web: side,
    native: side,
    screenshot: v.nullable(
      v.object({ src: v.string(), width: v.number(), height: v.number() }),
    ),
    missing: v.nullable(v.string()),
  }),
);

export type Recipe = v.InferOutput<typeof recipesSchema>[number];

export const recipes: readonly Recipe[] = v.parse(recipesSchema, recipesJson);

/** A recipe whose web and native code exist in the example apps. */
export type AvailableRecipe = Recipe & {
  readonly hook: NonNullable<Recipe["hook"]>;
  readonly web: NonNullable<Recipe["web"]>;
  readonly native: NonNullable<Recipe["native"]>;
};

function isAvailable(recipe: Recipe): recipe is AvailableRecipe {
  return (
    recipe.status === "available" &&
    recipe.hook !== null &&
    recipe.web !== null &&
    recipe.native !== null
  );
}

export const availableRecipes: readonly AvailableRecipe[] =
  recipes.filter(isAvailable);

export const plannedRecipes: readonly Recipe[] = recipes.filter(
  (recipe) => !isAvailable(recipe),
);

export function getRecipe(slug: string): AvailableRecipe | undefined {
  return availableRecipes.find((recipe) => recipe.slug === slug);
}

export function recipePath(slug: string): string {
  return `/recipes/${slug}`;
}

/** The `generateStaticParams` of `app/recipes/[slug]`: one page per available recipe. */
export function recipeStaticParams(): { slug: string }[] {
  return availableRecipes.map((recipe) => ({ slug: recipe.slug }));
}

/** The recipes that use a block, for its `/blocks` page. */
export function recipesFor(block: string): readonly Recipe[] {
  return recipes.filter((recipe) => recipe.block === block);
}

/** `npx shadcn add` for the shadcn components or the `@better-supabase` glue items. */
export function shadcnAdd(names: readonly string[], registry = false): string {
  const items = registry
    ? names.map((name) => `@better-supabase/${name}`)
    : names;

  return `npx shadcn add ${items.join(" ")}`;
}

/** The example file a snippet comes from, on GitHub. */
export function sourcePath(file: string): string {
  return `blob/main/${file}`;
}
