/**
 * Builds the UI recipes from the example apps. Each snippet is the code between
 * `// #region recipe:<slug>` and `// #endregion recipe:<slug>` in
 * `apps/examples/nextjs` (web) or `apps/examples/expo-powersync` (native), so
 * every snippet is code that typechecks and runs. It writes:
 *
 * - `apps/marketing/lib/recipes.json`, which `/recipes` renders (gitignored);
 * - `apps/docs/content/docs/registry/ui-recipes.mdx`, for the docs, `/llms.txt`
 *   and `/llms-full.txt`;
 * - `packages/better-supabase/skills/better-supabase/references/ui-recipes.md`,
 *   for agents.
 *
 * The docs page and the skill are committed, so `--write` (`pnpm recipes`)
 * writes them and `--check` (`pnpm recipes:check`, part of `pnpm verify`) fails
 * when they are stale. The marketing `build`, `dev`, `typecheck`, `lint` and
 * `test` tasks depend on the JSON (Turbo `//#recipes`).
 */
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { argv, exit } from "node:process";

import type { RecipeKind, RecipeSource, Side } from "./recipes/types.ts";

import { RECIPES } from "./recipes/sources.ts";
import { NATIVE_APP, WEB_APP } from "./recipes/types.ts";

const ROOT = join(import.meta.dirname, "..");
const RECIPES_FILE = join(ROOT, "apps/marketing/lib/recipes.json");
const DOCS_FILE = join(ROOT, "apps/docs/content/docs/registry/ui-recipes.mdx");

const SKILL_FILE = join(
  ROOT,
  "packages/better-supabase/skills/better-supabase/references/ui-recipes.md",
);

const SITE = "https://bettersupabase.com";

interface Snippet {
  readonly file: string;
  readonly code: string;
}

interface Recipe {
  readonly slug: string;
  readonly title: string;
  /** The primary block, `blocks[0]`. */
  readonly block: string;
  readonly blocks: readonly string[];
  readonly category: string | null;
  readonly kind: RecipeKind;
  readonly description: string;
  readonly status: "available" | "planned";
  readonly hook: { readonly name: string; readonly entry: string } | null;
  readonly web: (Side & { readonly snippet: Snippet }) | null;
  readonly native: (Side & { readonly snippet: Snippet }) | null;
  readonly screenshot: {
    readonly src: string;
    readonly width: number;
    readonly height: number;
  } | null;
  readonly note: string | null;
  readonly missing: string | null;
}

const REGION = /^\s*\/\/ #(region|endregion) recipe:([a-z0-9-]+)\s*$/;

/**
 * The code between the recipe's region markers in `file`, regions joined in
 * order.
 */
function extractRegion(source: string, slug: string, file = ""): string {
  const parts: string[] = [];
  let current: string[] | null = null;

  for (const line of source.split("\n")) {
    const marker = REGION.exec(line);

    if (marker?.[2] === slug) {
      if (marker[1] === "region") {
        if (current) {
          throw new Error(`${file}: nested region recipe:${slug}`);
        }

        current = [];
      } else {
        if (!current) {
          throw new Error(`${file}: #endregion recipe:${slug} without #region`);
        }

        parts.push(current.join("\n").trim());
        current = null;
      }

      continue;
    }

    if (marker) {
      continue;
    }

    current?.push(line);
  }

  if (current) {
    throw new Error(`${file}: region recipe:${slug} is not closed`);
  }

  if (parts.length === 0) {
    throw new Error(`${file}: no region recipe:${slug}`);
  }

  return `${parts.join("\n\n")}\n`;
}

function sourceFiles(dir: string): string[] {
  return readdirSync(join(ROOT, dir), { recursive: true, withFileTypes: true })
    .filter(
      (entry) =>
        entry.isFile() &&
        /\.(ts|tsx)$/.test(entry.name) &&
        !entry.parentPath.includes("node_modules"),
    )
    .map((entry) => relative(ROOT, join(entry.parentPath, entry.name)));
}

/** Every `recipe:` region in the examples names a recipe with that file. */
function checkRegions(recipes: readonly RecipeSource[]): void {
  const owners = new Map<string, string[]>();

  for (const recipe of recipes) {
    for (const side of [recipe.web, recipe.native]) {
      if (side) {
        owners.set(side.file, [...(owners.get(side.file) ?? []), recipe.slug]);
      }
    }
  }

  for (const file of [
    ...sourceFiles(`${WEB_APP}/src`),
    ...sourceFiles(`${NATIVE_APP}/src`),
  ]) {
    for (const line of readFileSync(join(ROOT, file), "utf-8").split("\n")) {
      const slug = REGION.exec(line)?.[2];

      if (slug && !owners.get(file)?.includes(slug)) {
        throw new Error(
          `build-recipes: ${file} has a region recipe:${slug}, which no recipe in scripts/build-recipes.ts reads from that file.`,
        );
      }
    }
  }
}

function withSnippet(side: Side | undefined, slug: string) {
  if (!side) {
    return null;
  }

  const source = readFileSync(join(ROOT, side.file), "utf-8");

  return {
    ...side,
    snippet: { file: side.file, code: extractRegion(source, slug, side.file) },
  };
}

/** Width and height from the PNG's IHDR chunk, at the 2x scale it was taken in. */
function pngSize(file: string) {
  const png = readFileSync(join(ROOT, "apps/marketing/public/recipes", file));

  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}

function buildRecipes(): readonly Recipe[] {
  checkRegions(RECIPES);

  const screenshots = new Set(
    readdirSync(join(ROOT, "apps/marketing/public/recipes")),
  );

  return RECIPES.map((recipe): Recipe => {
    const available = recipe.web !== undefined;

    if (!available && recipe.missing === undefined) {
      throw new Error(
        `build-recipes: the recipe "${recipe.slug}" has no web code, so it needs a missing note.`,
      );
    }

    const screenshot = `${recipe.slug}.png`;

    return {
      slug: recipe.slug,
      title: recipe.title,
      block: recipe.blocks[0],
      blocks: recipe.blocks,
      category: recipe.category ?? null,
      kind: recipe.kind,
      description: recipe.description,
      status: available ? "available" : "planned",
      hook: available ? (recipe.hook ?? null) : null,
      web: withSnippet(recipe.web, recipe.slug),
      native: withSnippet(recipe.native, recipe.slug),
      screenshot:
        available && screenshots.has(screenshot)
          ? { src: `/recipes/${screenshot}`, ...pngSize(screenshot) }
          : null,
      note: recipe.note ?? null,
      missing: recipe.missing ?? null,
    };
  });
}

const fence = (language: string, code: string, title?: string): string =>
  `\`\`\`${language}${title ? ` title="${title}"` : ""}\n${code}\`\`\``;

const blockLinks = (blocks: readonly string[]): string =>
  blocks.map((name) => `[${name}](${SITE}/blocks/${name})`).join(", ");

/** What the recipe calls, and the blocks it needs installed. */
function recipeUses(recipe: Recipe): string {
  const call = recipe.hook
    ? `${recipe.native ? "Both sides call" : "It calls"} \`${recipe.hook.name}\` from \`${recipe.hook.entry}\``
    : "It loads its data on the server through the block's client";

  const install =
    recipe.blocks.length === 1
      ? `the [${recipe.block} block](${SITE}/blocks/${recipe.block}) must be installed`
      : `the ${blockLinks(recipe.blocks)} blocks must be installed`;

  return `${call}; ${install} (\`npx better-supabase add ${recipe.blocks.join(" ")}\`).`;
}

/** One recipe as Markdown, shared by the docs page and the skill. */
function recipeMarkdown(recipe: Recipe, heading: string): string {
  if (!recipe.web) {
    return "";
  }

  const lines = [
    `${heading} ${recipe.title}`,
    "",
    `${recipe.description} ${recipeUses(recipe)} Page: ${SITE}/recipes/${recipe.slug}.`,
    "",
    ...(recipe.web.components.length > 0
      ? [
          "Web, with shadcn components:",
          "",
          fence("bash", `npx shadcn add ${recipe.web.components.join(" ")}\n`),
        ]
      : ["Web, with no shadcn components."]),
  ];

  if (recipe.web.glue.length > 0) {
    lines.push(
      "",
      fence(
        "bash",
        `npx shadcn add ${recipe.web.glue.map((item) => `@better-supabase/${item}`).join(" ")}\n`,
      ),
    );
  }

  if (recipe.note) {
    lines.push("", recipe.note);
  }

  lines.push(
    "",
    fence("tsx", recipe.web.snippet.code, recipe.web.snippet.file),
  );

  if (!recipe.native) {
    return lines.join("\n");
  }

  lines.push(
    "",
    `React Native, with ${recipe.native.components.map((name) => `\`${name}\``).join(", ")} from \`react-native\`:`,
    "",
  );

  if (recipe.native.glue.length > 0) {
    lines.push(
      fence(
        "bash",
        `npx shadcn add ${recipe.native.glue.map((item) => `@better-supabase/${item}`).join(" ")}\n`,
      ),
      "",
    );
  }

  lines.push(
    fence("tsx", recipe.native.snippet.code, recipe.native.snippet.file),
  );

  return lines.join("\n");
}

/** A Markdown table with padded columns, the way the formatter writes it. */
function table(rows: readonly (readonly string[])[]): string {
  const widths = (rows[0] ?? []).map((_, column) =>
    Math.max(...rows.map((row) => (row[column] ?? "").length)),
  );

  const line = (row: readonly string[]): string =>
    `| ${row.map((cell, column) => cell.padEnd(widths[column] ?? 0)).join(" | ")} |`;

  const [head, ...body] = rows;

  return [
    line(head ?? []),
    line(widths.map((width) => "-".repeat(width))),
    ...body.map(line),
  ].join("\n");
}

/** The "Planned" section, or nothing while every recipe is available. */
function plannedSection(
  recipes: readonly Recipe[],
  lead: readonly string[] = [],
): readonly string[] {
  const planned = recipes.filter((recipe) => recipe.status === "planned");

  if (planned.length === 0) {
    return [];
  }

  return [
    "## Planned",
    "",
    ...lead,
    table([
      ["Recipe", "Blocks", "Waits for"],
      ...planned.map((recipe) => [
        recipe.title,
        recipe.blocks.map((name) => `\`${name}\``).join(", "),
        recipe.missing ?? "",
      ]),
    ]),
    "",
  ];
}

const INTRO = `better-supabase ships no visible UI components. A recipe builds one component or one screen from your own shadcn components (web) or React Native primitives (native) and one or more blocks. Every recipe has web code; the ones that fit a phone also have native code, which calls the same hook. Both come from the example apps, \`apps/examples/nextjs\` and \`apps/examples/expo-powersync\`, so they typecheck and run.`;

function renderDocsPage(recipes: readonly Recipe[]): string {
  const available = recipes.filter((recipe) => recipe.status === "available");

  return [
    "---",
    "title: UI recipes",
    "description: Build components and screens for the blocks, such as notifications, search, onboarding, comments, members, API keys, the audit log, billing and settings, from shadcn or React Native components and the blocks' hooks.",
    "---",
    "",
    "{/* Generated by scripts/build-recipes.ts from the example apps. Edit the examples or the script, then run `pnpm recipes`. */}",
    "",
    INTRO,
    "",
    `Each recipe also has a page at [bettersupabase.com/recipes](${SITE}/recipes) with a screenshot. The native snippets use plain React Native primitives, so they run without a styling library; [React Native Reusables](https://reactnativereusables.com) serves shadcn-style native components from a working registry if you want them.`,
    "",
    ...available.flatMap((recipe) => [recipeMarkdown(recipe, "##"), ""]),
    ...plannedSection(recipes),
  ].join("\n");
}

function renderSkill(recipes: readonly Recipe[]): string {
  const available = recipes.filter((recipe) => recipe.status === "available");

  return [
    "# UI recipes",
    "",
    "<!-- Generated by scripts/build-recipes.ts from the example apps. -->",
    "",
    INTRO,
    "",
    "Build the UI this way: add the shadcn components the recipe lists, install the glue items, then adapt the snippet to the app (its i18n, routes and API schema). Never add a better-supabase UI package; there is none.",
    "",
    ...available.flatMap((recipe) => [recipeMarkdown(recipe, "##"), ""]),
    ...plannedSection(recipes, [
      "These have no example code yet. Build them from the block's TypeScript client in a server action or loader, or from its hook where it has one.",
      "",
    ]),
  ].join("\n");
}

if (import.meta.main) {
  try {
    const recipes = buildRecipes();
    mkdirSync(dirname(RECIPES_FILE), { recursive: true });
    writeFileSync(RECIPES_FILE, `${JSON.stringify(recipes, null, 2)}\n`);

    const outputs = new Map([
      [DOCS_FILE, renderDocsPage(recipes)],
      [SKILL_FILE, renderSkill(recipes)],
    ]);

    if (argv.includes("--write")) {
      for (const [file, contents] of outputs) {
        writeFileSync(file, contents);
      }
    }

    if (argv.includes("--check")) {
      const stale = [...outputs]
        .filter(([file, contents]) => readFileSync(file, "utf-8") !== contents)
        .map(([file]) => relative(ROOT, file));

      if (stale.length > 0) {
        console.error(
          `build-recipes: ${stale.join(", ")} is stale. Run \`pnpm recipes\`.`,
        );
        exit(1);
      }
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    exit(1);
  }
}
