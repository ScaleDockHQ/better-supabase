import { describe, expect, test } from "vitest";

import { blockGroups, blocks, getBlock } from "../../lib/blocks";
import {
  blockMarkdown,
  blocksIndexMarkdown,
  recipeMarkdown,
  recipesIndexMarkdown,
} from "../../lib/markdown";
import {
  availableRecipes,
  plannedRecipes,
  recipePrompt,
  recipesFor,
  shadcnAdd,
} from "../../lib/recipes";

const site = {
  url: "https://example.com",
  github: "https://github.com/acme/x",
};

describe("markdown mirrors", () => {
  test("a block page has the install command and links its dependencies", () => {
    const block = blocks.find((candidate) => candidate.requires.length > 0);

    expect(block).toBeDefined();

    if (!block) {
      return;
    }

    const markdown = blockMarkdown(block, {
      site,
      installed: [...block.requires, block.name],
      recipes: recipesFor(block.name),
    });

    expect(markdown).toMatch(new RegExp(`^# ${block.title}\\n`));
    expect(markdown).toContain(`npx better-supabase sql add ${block.name}`);
    expect(markdown).toContain(
      `(https://example.com/blocks/${block.requires[0]}.md)`,
    );
  });

  test("the blocks index lists every block once", () => {
    const markdown = blocksIndexMarkdown(blockGroups(), site);

    for (const block of blocks) {
      expect(markdown).toContain(`/blocks/${block.name}.md)`);
    }

    expect(markdown).toContain(`> ${blocks.length} SQL modules`);
  });

  test("a recipe page has both platforms and links its block", () => {
    const recipe = availableRecipes.find((each) => each.native !== null);

    expect(recipe).toBeDefined();

    if (!recipe) {
      return;
    }

    const markdown = recipeMarkdown(recipe, site);

    expect(getBlock(recipe.block)).toBeDefined();
    expect(markdown).toContain("## Web (Next.js)");
    expect(markdown).toContain("## Native (Expo)");
    expect(markdown).toContain(
      `(https://example.com/blocks/${recipe.block}.md)`,
    );
    expect(markdown).toContain("## Prompt");
    expect(markdown).toContain(recipePrompt(recipe, "web", site.url));
    expect(markdown).toContain(recipePrompt(recipe, "native", site.url));
    expect(markdown).not.toContain(shadcnAdd(recipe.native?.components ?? []));
  });

  test("the recipes index links the available recipes", () => {
    const markdown = recipesIndexMarkdown(
      availableRecipes,
      plannedRecipes,
      site,
    );

    for (const recipe of availableRecipes) {
      expect(markdown).toContain(`/recipes/${recipe.slug}.md)`);
    }
  });
});
