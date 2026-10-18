import * as v from "valibot";

import type { RecipePlatform } from "./recipe-platform";

import { blockCategories, getBlock } from "./blocks";
import { type RecipeSummary, recipeKinds } from "./recipe-filter";
// Written by scripts/build-recipes.ts from the example apps' region markers
// before every build, dev, typecheck, lint and test run (Turbo `//#recipes`).
import recipesJson from "./recipes.json";

export { recipePath } from "./recipe-filter";

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
    blocks: v.array(v.string()),
    kind: v.picklist(recipeKinds),
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

/** A recipe whose web code exists in the example app; native code is optional. */
export type AvailableRecipe = Recipe & {
  readonly web: NonNullable<Recipe["web"]>;
};

type RecipeSide = NonNullable<Recipe["web"]>;

function isAvailable(recipe: Recipe): recipe is AvailableRecipe {
  return recipe.status === "available" && recipe.web !== null;
}

export const availableRecipes: readonly AvailableRecipe[] =
  recipes.filter(isAvailable);

export const plannedRecipes: readonly Recipe[] = recipes.filter(
  (recipe) => !isAvailable(recipe),
);

export function getRecipe(slug: string): AvailableRecipe | undefined {
  return availableRecipes.find((recipe) => recipe.slug === slug);
}

/** The `generateStaticParams` of `app/(recipes)/recipes/[slug]`: one page per available recipe. */
export function recipeStaticParams(): { slug: string }[] {
  return availableRecipes.map((recipe) => ({ slug: recipe.slug }));
}

/** The platforms a recipe has code for: always the web, and native where it fits a phone. */
export function recipePlatformsOf(recipe: Recipe): RecipePlatform[] {
  return [
    ...(recipe.web ? (["web"] as const) : []),
    ...(recipe.native ? (["native"] as const) : []),
  ];
}

/** A recipe's code on one platform, for a platform it has. */
export function recipeSide(
  recipe: AvailableRecipe,
  platform: RecipePlatform,
): RecipeSide {
  const side = recipe[platform];

  if (!side) {
    throw new Error(`The recipe "${recipe.slug}" has no ${platform} code.`);
  }

  return side;
}

/** The fields a tile and the `/recipes` filters need, without the code. */
export function recipeSummary(recipe: Recipe): RecipeSummary {
  return {
    slug: recipe.slug,
    title: recipe.title,
    description: recipe.description,
    block: recipe.block,
    blocks: recipe.blocks,
    category: recipeCategory(recipe),
    kind: recipe.kind,
    platforms: recipePlatformsOf(recipe),
    hook: recipe.hook?.name ?? null,
    screenshot: recipe.screenshot,
  };
}

/** `npx better-supabase sql add` for every block the recipe uses. */
export function recipeInstall(recipe: Recipe): string {
  return `npx better-supabase sql add ${recipe.blocks.join(" ")}`;
}

/** A recipe's category is its primary block's. */
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

/** The recipes that use a block, as the primary block or another one, for its `/blocks` page. */
export function recipesFor(block: string): readonly Recipe[] {
  return recipes.filter((recipe) => recipe.blocks.includes(block));
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

  const side = recipeSide(recipe, platform);

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
      ? recipe.hook
        ? "The recipe needs no glue: the hook calls the block from the client."
        : "The recipe needs no glue: it calls the block's client on the server."
      : `Add the glue from the better-supabase registry: \`${shadcnAdd(side.glue, true)}\`. The items are copied into the app, so edit them as needed.`;

  const others = recipe.blocks.slice(1).map((name) => `\`${name}\``);

  const uses =
    others.length === 0
      ? `It uses the better-supabase \`${recipe.block}\` block (${block.title}).`
      : `It uses the better-supabase \`${recipe.block}\` block (${block.title}) with ${others.join(", ")}.`;

  const calls = recipe.hook
    ? `It calls the hook \`${recipe.hook.name}\` from \`${recipe.hook.entry}\`.`
    : "It loads its data on the server through the block's client.";

  const write = recipe.hook
    ? `Call \`${recipe.hook.name}\` from \`${recipe.hook.entry}\``
    : "Load the data on the server with the block's client";

  return [
    `Build "${recipe.title}" in ${PLATFORM_TARGET[platform]}. ${recipe.description}`,
    `${uses} ${calls}`,
    "Steps:",
    [
      `1. If the app doesn't have ${recipe.blocks.length === 1 ? "the block" : "the blocks"} yet, add the SQL with \`${recipeInstall(recipe)}\` and apply the migration.`,
      `2. ${components}`,
      `3. ${glue}`,
      `4. Write the ${recipe.kind === "screen" ? "screen" : "component"}. ${write}, starting from the recipe's snippet (\`${side.snippet.file}\`). Adapt it to the app's existing components, styling and data loading instead of copying it as is.`,
      `5. Check the result against the recipe and the block's docs: it typechecks, ${recipe.hook ? "it calls the same hook" : "it reads the same block data"}, and it handles the loading and empty states the snippet handles.`,
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
