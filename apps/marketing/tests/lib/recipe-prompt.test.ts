import { describe, expect, test } from "vitest";

import { getBlock } from "../../lib/blocks";
import { parsePlatform } from "../../lib/recipe-platform";
import {
  availableRecipes,
  recipePlatformsOf,
  recipePrompt,
  recipeSide,
  shadcnAdd,
} from "../../lib/recipes";

const SITE = "https://example.com";

const cases = availableRecipes.flatMap((recipe) =>
  recipePlatformsOf(recipe).map(
    (platform) => [recipe.slug, platform, recipe] as const,
  ),
);

describe("recipePrompt", () => {
  test.each(cases)(
    "%s on %s names the goal, the blocks and the hook",
    (_slug, platform, recipe) => {
      const prompt = recipePrompt(recipe, platform, SITE);

      expect(prompt).toContain(`"${recipe.title}"`);
      expect(prompt).toContain(recipe.description);
      expect(prompt).toContain(
        `npx better-supabase add ${recipe.blocks.join(" ")}`,
      );

      for (const text of recipe.hook
        ? [recipe.hook.name, recipe.hook.entry]
        : []) {
        expect(prompt).toContain(text);
      }

      expect(prompt).toContain(recipeSide(recipe, platform).snippet.file);
    },
  );

  test.each(
    cases.filter(
      ([, platform, recipe]) => recipeSide(recipe, platform).glue.length > 0,
    ),
  )("%s on %s installs that platform's glue", (_slug, platform, recipe) => {
    expect(recipePrompt(recipe, platform, SITE)).toContain(
      shadcnAdd(recipeSide(recipe, platform).glue, true),
    );
  });

  test.each(
    availableRecipes.flatMap((recipe) =>
      recipe.native
        ? [[recipe.slug, { ...recipe, native: recipe.native }] as const]
        : [],
    ),
  )(
    "%s gives shadcn commands on the web and React Native primitives on native",
    (_slug, recipe) => {
      const web = recipePrompt(recipe, "web", SITE);
      const native = recipePrompt(recipe, "native", SITE);

      expect(web).toContain(shadcnAdd(recipe.web.components));
      expect(web).toContain("React web app");
      expect(web).not.toContain(recipe.native.snippet.file);
      expect(native).not.toContain(shadcnAdd(recipe.native.components));
      expect(native).toContain("React Native");
      expect(native).toContain("`react-native`");
      expect(native).not.toContain(recipe.web.snippet.file);
    },
  );

  test.each(cases)(
    "%s on %s links the mirror and the block docs",
    (_slug, platform, recipe) => {
      const prompt = recipePrompt(recipe, platform, SITE);
      const docs = getBlock(recipe.block)?.docs ?? "";

      expect(prompt).toContain(`${SITE}/recipes/${recipe.slug}.md`);
      expect(prompt).toContain(docs.startsWith("/") ? `${SITE}${docs}` : docs);
    },
  );

  test("the prompt has no em dashes", () => {
    for (const [, platform, recipe] of cases) {
      expect(recipePrompt(recipe, platform, SITE)).not.toContain("\u2014");
    }
  });
});

describe("parsePlatform", () => {
  test("reads native and falls back to web", () => {
    expect(parsePlatform("native")).toBe("native");
    expect(parsePlatform("web")).toBe("web");
    expect(parsePlatform(null)).toBe("web");
    expect(parsePlatform("ios")).toBe("web");
  });
});
