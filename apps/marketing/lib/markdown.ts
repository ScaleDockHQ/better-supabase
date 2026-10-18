import type { BlockGroup, CatalogBlock } from "./blocks";
import type { AvailableRecipe, Recipe } from "./recipes";

import { configSnippet, installCommand } from "./blocks";
import { shadcnAdd } from "./recipes";

/** The headers of every Markdown mirror, the same ones the docs app sends. */
export const markdownHeaders: HeadersInit = {
  "Content-Type": "text/markdown; charset=utf-8",
  Vary: "Accept",
};

export interface MarkdownSite {
  /** The site origin, without a trailing slash. */
  readonly url: string;
  readonly github: string;
}

const absolute = (site: MarkdownSite, path: string): string =>
  path.startsWith("/") ? `${site.url}${path}` : path;

const fence = (language: string, code: string): string =>
  [`\`\`\`${language}`, code.trimEnd(), "```"].join("\n");

const blockLink = (site: MarkdownSite, name: string): string =>
  `[${name}](${site.url}/blocks/${name}.md)`;

const list = (items: readonly string[]): string =>
  items.map((item) => `- ${item}`).join("\n");

/** `/blocks/<name>.md`: one block as Markdown for agents and LLM crawlers. */
export function blockMarkdown(
  block: CatalogBlock,
  options: {
    readonly site: MarkdownSite;
    /** The modules `sql add` installs, dependencies first. */
    readonly installed: readonly string[];
    readonly recipes: readonly Recipe[];
  },
): string {
  const { site, installed, recipes } = options;
  const dependencies = installed.filter((name) => name !== block.name);

  const sections = [
    `# ${block.title}`,
    `> ${block.description}`,
    list([
      `Category: ${block.category}`,
      `Module: \`${block.name}\``,
      `Modes: ${block.modes.map((mode) => `\`${mode}\``).join(", ")}`,
      `Docs: ${absolute(site, block.docs)}`,
      `Page: ${site.url}/blocks/${block.name}`,
    ]),
    "## Install",
    fence("bash", installCommand(block.name)),
  ];

  if (dependencies.length > 0) {
    sections.push(
      `The command also installs ${dependencies.map((name) => `\`${name}\``).join(", ")}.`,
    );
  }

  sections.push(
    "## Configure",
    "Add the block to `better-supabase.config.ts`:",
    fence("ts", configSnippet(block, installed)),
    "## Client",
  );

  if (block.react) {
    sections.push(
      `The React hooks are in \`${block.react.subpath}\`. They return data and actions and render no UI. Source: ${site.github}/blob/main/${block.react.source}`,
    );
  } else if (block.subpath) {
    sections.push(
      `The block has no React entry yet. Its server-side TypeScript is in \`${block.subpath}\`.`,
    );
  } else {
    sections.push(
      "The block is SQL only: call its functions from your policies, RPCs and the other modules.",
    );
  }

  if (block.events.length > 0) {
    sections.push(
      "## Events",
      list(block.events.map((event) => `\`${event}\``)),
    );
  }

  if (block.requires.length > 0 || block.integrates.length > 0) {
    sections.push("## Related blocks");

    if (block.requires.length > 0) {
      sections.push(
        `Requires: ${block.requires.map((name) => blockLink(site, name)).join(", ")}`,
      );
    }

    if (block.integrates.length > 0) {
      sections.push(
        `Works with: ${block.integrates.map((name) => blockLink(site, name)).join(", ")}`,
      );
    }
  }

  if (recipes.length > 0) {
    sections.push(
      "## Recipes",
      list(
        recipes.map((recipe) =>
          recipe.status === "available"
            ? `[${recipe.title}](${site.url}/recipes/${recipe.slug}.md): ${recipe.description}`
            : `${recipe.title} (planned): ${recipe.description}`,
        ),
      ),
    );
  }

  return `${sections.join("\n\n")}\n`;
}

/** `/recipes/<slug>.md`: one recipe as Markdown. */
export function recipeMarkdown(
  recipe: AvailableRecipe,
  site: MarkdownSite,
): string {
  const sides = [
    ["Web (Next.js)", recipe.web],
    ["Native (Expo)", recipe.native],
  ] as const;

  const sections = [
    `# ${recipe.title}`,
    `> ${recipe.description}`,
    list([
      `Block: ${blockLink(site, recipe.block)}`,
      `Hook: \`${recipe.hook.name}\` from \`${recipe.hook.entry}\``,
      `Page: ${site.url}/recipes/${recipe.slug}`,
    ]),
    "## Install the block",
    fence("bash", installCommand(recipe.block)),
  ];

  for (const [label, side] of sides) {
    sections.push(`## ${label}`);

    if (side.components.length > 0) {
      sections.push(
        "Add the shadcn components:",
        fence("bash", shadcnAdd(side.components)),
      );
    }

    if (side.glue.length > 0) {
      sections.push(
        "Add the glue from the better-supabase registry:",
        fence("bash", shadcnAdd(side.glue, true)),
      );
    }

    sections.push(
      `From \`${side.snippet.file}\` (${site.github}/blob/main/${side.file}):`,
      fence("tsx", side.snippet.code),
    );
  }

  return `${sections.join("\n\n")}\n`;
}

/** `/blocks.md`: every block by category, linked to its Markdown page. */
export function blocksIndexMarkdown(
  groups: readonly BlockGroup[],
  site: MarkdownSite,
): string {
  const total = groups.reduce((sum, group) => sum + group.blocks.length, 0);

  const sections = [
    "# better-supabase blocks",
    `> ${total} SQL modules with typed clients. Install one with \`npx better-supabase sql add <name>\`.`,
  ];

  for (const group of groups) {
    if (group.blocks.length === 0) {
      continue;
    }

    sections.push(
      `## ${group.category}`,
      list(
        group.blocks.map(
          (block) =>
            `[${block.title}](${site.url}/blocks/${block.name}.md): ${block.description}`,
        ),
      ),
    );
  }

  return `${sections.join("\n\n")}\n`;
}

/** `/recipes.md`: the available and planned recipes. */
export function recipesIndexMarkdown(
  available: readonly AvailableRecipe[],
  planned: readonly Recipe[],
  site: MarkdownSite,
): string {
  const sections = [
    "# better-supabase recipes",
    "> UI for a block, built from shadcn components and the block's React hooks, for Next.js and Expo.",
    "## Available",
    list(
      available.map(
        (recipe) =>
          `[${recipe.title}](${site.url}/recipes/${recipe.slug}.md): ${recipe.description}`,
      ),
    ),
  ];

  if (planned.length > 0) {
    sections.push(
      "## Planned",
      list(planned.map((recipe) => `${recipe.title}: ${recipe.description}`)),
    );
  }

  return `${sections.join("\n\n")}\n`;
}
