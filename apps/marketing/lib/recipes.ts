import * as v from "valibot";

import type { RecipePlatform } from "./recipe-platform";

import { blockCategories, getBlock } from "./blocks";
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

export function recipePath(slug: string): `/recipes/${string}` {
  return `/recipes/${slug}`;
}

/** The `generateStaticParams` of `app/(recipes)/recipes/[slug]`: one page per available recipe. */
export function recipeStaticParams(): { slug: string }[] {
  return availableRecipes.map((recipe) => ({ slug: recipe.slug }));
}

/** A recipe's category is its block's. */
export function recipeCategory(recipe: Recipe): string {
  const block = getBlock(recipe.block);

  if (!block) {
    throw new Error(
      `The recipe "${recipe.slug}" uses the block "${recipe.block}", which the catalog lacks.`,
    );
  }

  return block.category;
}

export interface RecipeGroup {
  readonly category: string;
  readonly available: readonly AvailableRecipe[];
  readonly planned: readonly Recipe[];
}

/** The recipes per block category, in catalog order, without empty categories. */
export function recipeGroups(): RecipeGroup[] {
  return blockCategories
    .map((category) => ({
      category,
      available: availableRecipes.filter(
        (recipe) => recipeCategory(recipe) === category,
      ),
      planned: plannedRecipes.filter(
        (recipe) => recipeCategory(recipe) === category,
      ),
    }))
    .filter((group) => group.available.length + group.planned.length > 0);
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

const PLATFORM_TARGET = {
  web: "a React web app that uses shadcn/ui components",
  native: "a React Native app built with Expo",
} as const satisfies Record<RecipePlatform, string>;

const codeList = (names: readonly string[]): string =>
  names.map((name) => `\`${name}\``).join(", ");

/**
 * A prompt for a coding agent that builds the recipe on one platform. It
 * names the commands and the hook, and links the Markdown mirror and the
 * block's docs so the agent can read the full code.
 */
export function recipePrompt(
  recipe: AvailableRecipe,
  platform: RecipePlatform,
  siteUrl: string,
): string {
  const block = getBlock(recipe.block);

  if (!block) {
    throw new Error(
      `The recipe "${recipe.slug}" uses the block "${recipe.block}", which the catalog lacks.`,
    );
  }

  const side = recipe[platform];

  const docs = block.docs.startsWith("/")
    ? `${siteUrl}${block.docs}`
    : block.docs;

  const components =
    side.components.length === 0
      ? "The recipe needs no extra UI components."
      : platform === "web"
        ? `Add the shadcn components the recipe uses: \`${shadcnAdd(side.components)}\`.`
        : `The recipe uses ${codeList(side.components)} from \`react-native\`, so it needs no extra UI library. Use the app's own components if it has them.`;

  const glue =
    side.glue.length === 0
      ? "The recipe needs no glue: the hook calls the block from the client."
      : `Add the glue from the better-supabase registry: \`${shadcnAdd(side.glue, true)}\`. The items are copied into the app, so edit them as needed.`;

  return [
    `Build "${recipe.title}" in ${PLATFORM_TARGET[platform]}. ${recipe.description}`,
    `It uses the better-supabase \`${recipe.block}\` block (${block.title}) and its hook \`${recipe.hook.name}\` from \`${recipe.hook.entry}\`.`,
    "Steps:",
    [
      `1. If the app doesn't have the block yet, add its SQL with \`npx better-supabase sql add ${recipe.block}\` and apply the migration.`,
      `2. ${components}`,
      `3. ${glue}`,
      `4. Write the component. Call \`${recipe.hook.name}\` from \`${recipe.hook.entry}\`, starting from the recipe's snippet (\`${side.snippet.file}\`). Adapt it to the app's existing components, styling and data loading instead of copying it as is.`,
      "5. Check the result against the recipe and the block's docs: it typechecks, it calls the same hook, and it handles the loading and empty states the snippet handles.",
    ].join("\n"),
    "Read the full code first:",
    [
      `- Recipe: ${siteUrl}/recipes/${recipe.slug}.md`,
      `- Block docs: ${docs}`,
    ].join("\n"),
  ].join("\n\n");
}

/** The example file a snippet comes from, on GitHub. */
export function sourcePath(file: string): string {
  return `blob/main/${file}`;
}
