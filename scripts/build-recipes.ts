/**
 * Builds the UI recipes from the example apps. Each snippet is the code
 * between `// #region recipe:<slug>` and `// #endregion recipe:<slug>` in
 * `apps/examples/nextjs` (web) or `apps/examples/expo-powersync` (native),
 * so every snippet is code that typechecks and runs. It writes:
 *
 * - `apps/marketing/lib/recipes.json`, which `/recipes` renders (gitignored);
 * - `apps/docs/content/docs/registry/ui-recipes.mdx`, for the docs, `/llms.txt`
 *   and `/llms-full.txt`;
 * - `packages/better-supabase/skills/better-supabase/references/ui-recipes.md`,
 *   for agents.
 *
 * The docs page and the skill are committed, so `--write` (`pnpm recipes`)
 * writes them and `--check` (`pnpm recipes:check`, part of `pnpm verify`)
 * fails when they are stale. The marketing `build`, `dev`, `typecheck`, `lint` and `test`
 * tasks depend on the JSON (Turbo `//#recipes`).
 */
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { argv, exit } from "node:process";

const ROOT = join(import.meta.dirname, "..");
const WEB_APP = "apps/examples/nextjs";
const NATIVE_APP = "apps/examples/expo-powersync";
const RECIPES_FILE = join(ROOT, "apps/marketing/lib/recipes.json");
const DOCS_FILE = join(ROOT, "apps/docs/content/docs/registry/ui-recipes.mdx");
const SKILL_FILE = join(
  ROOT,
  "packages/better-supabase/skills/better-supabase/references/ui-recipes.md",
);
const SITE = "https://bettersupabase.com";

interface Side {
  /** The example file, relative to the repo root. */
  readonly file: string;
  /** Web: shadcn components (`npx shadcn add ...`). Native: React Native primitives. */
  readonly components: readonly string[];
  /** `@better-supabase/<item>` registry items the snippet imports. */
  readonly glue: readonly string[];
}

interface RecipeSource {
  readonly slug: string;
  readonly title: string;
  /** The SQL module the recipe's hook calls. */
  readonly block: string;
  readonly description: string;
  /** The hook both sides call, and the entry it comes from. */
  readonly hook: { readonly name: string; readonly entry: string };
  readonly web?: Side;
  readonly native?: Side;
  /** For a planned recipe: what has to ship first. */
  readonly missing?: string;
}

const RECIPES: readonly RecipeSource[] = [
  {
    slug: "notification-bell",
    title: "Notification bell",
    block: "notifications",
    description:
      "A header button with the unread count, which updates when a notification arrives or is read.",
    hook: {
      name: "useNotifications",
      entry: "better-supabase/blocks/notifications/react",
    },
    web: {
      file: `${WEB_APP}/src/features/notifications/components/unread-badge.tsx`,
      components: ["badge", "button"],
      glue: ["notifications-actions-next"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/notification-bell.tsx`,
      components: ["Pressable", "Text", "View"],
      glue: ["blocks"],
    },
  },
  {
    slug: "notification-list",
    title: "Notification list",
    block: "notifications",
    description:
      "The caller's latest notifications with an unread marker, loaded again on every change.",
    hook: {
      name: "useNotifications",
      entry: "better-supabase/blocks/notifications/react",
    },
    web: {
      file: `${WEB_APP}/src/features/notifications/components/notification-list.tsx`,
      components: ["badge", "empty", "skeleton"],
      glue: ["notifications-actions-next"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/notification-list.tsx`,
      components: ["ActivityIndicator", "FlatList", "Text", "View"],
      glue: ["blocks"],
    },
  },
  {
    slug: "command-search",
    title: "Command search",
    block: "search",
    description:
      "A search dialog over the search index, with favorites and recents before the user types.",
    hook: {
      name: "useCommandSearch",
      entry: "better-supabase/blocks/search/react",
    },
    web: {
      file: `${WEB_APP}/src/features/search/components/command-search.tsx`,
      components: ["button", "dialog", "input"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/command-search.tsx`,
      components: [
        "Modal",
        "Pressable",
        "SectionList",
        "Text",
        "TextInput",
        "View",
      ],
      glue: [],
    },
  },
  {
    slug: "onboarding-checklist",
    title: "Onboarding checklist",
    block: "onboarding",
    description:
      "The organization's getting-started steps with progress, hidden once every step is done.",
    hook: {
      name: "useOnboarding",
      entry: "better-supabase/blocks/onboarding/react",
    },
    web: {
      file: `${WEB_APP}/src/features/dashboard/components/onboarding-card.tsx`,
      components: ["button", "card", "progress", "skeleton"],
      glue: ["onboarding-checklist"],
    },
    native: {
      file: `${NATIVE_APP}/src/components/onboarding-checklist.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: ["onboarding-checklist"],
    },
  },
  {
    slug: "comment-thread",
    title: "Comment thread",
    block: "comments",
    description:
      "A record's comments with their authors and a form to add one, kept current after each write.",
    hook: {
      name: "useComments",
      entry: "better-supabase/blocks/comments/react",
    },
    web: {
      file: `${WEB_APP}/src/features/customers/components/comment-thread.tsx`,
      components: ["button", "field", "skeleton", "textarea"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/comment-thread.tsx`,
      components: [
        "ActivityIndicator",
        "Button",
        "FlatList",
        "Text",
        "TextInput",
        "View",
      ],
      glue: [],
    },
  },
  {
    slug: "org-switcher",
    title: "Organization switcher",
    block: "organizations",
    description:
      "A menu of the user's organizations that switches the active one and refreshes the session for its tenant claim.",
    hook: {
      name: "useOrganizations",
      entry: "better-supabase/blocks/organizations/react",
    },
    web: {
      file: `${WEB_APP}/src/features/organization/components/organization-switcher-menu.tsx`,
      components: ["dropdown-menu", "sidebar"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/organization-switcher.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "plan-picker",
    title: "Plan picker",
    block: "billing",
    description:
      "The plans with their prices and a checkout button each. Checkout starts in a server action or API route that holds the Stripe key, and the client opens the URL it returns.",
    hook: {
      name: "usePlanPicker",
      entry: "better-supabase/blocks/billing/react",
    },
    web: {
      file: `${WEB_APP}/src/features/billing/components/plan-picker.tsx`,
      components: ["button", "card"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/plan-picker.tsx`,
      components: ["ActivityIndicator", "Pressable", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "usage-meter",
    title: "Usage meter",
    block: "usage",
    description:
      "This period's usage per meter against the plan's quota, with the reset date.",
    hook: {
      name: "useUsageMeter",
      entry: "better-supabase/blocks/usage/react",
    },
    web: {
      file: `${WEB_APP}/src/features/dashboard/components/usage-card.tsx`,
      components: ["card", "progress", "skeleton"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/usage-meter.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "feature-gate",
    title: "Feature gate",
    block: "entitlements",
    description:
      "Content shown only when the active organization's plan includes a feature, read from the session's features claim and updated when the session refreshes.",
    hook: {
      name: "useFeatureGate",
      entry: "better-supabase/blocks/entitlements/react",
    },
    web: {
      file: `${WEB_APP}/src/features/billing/components/feature-gate.tsx`,
      components: ["button", "skeleton"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/feature-gate.tsx`,
      components: ["ActivityIndicator", "Text", "View"],
      glue: [],
    },
  },
  {
    slug: "settings-layout",
    title: "Settings layout",
    block: "settings",
    description:
      "Settings pages generated from the settings definition: a section per scope and a control per key, picked by the kind its schema declares.",
    hook: {
      name: "useSettings",
      entry: "better-supabase/blocks/settings/react",
    },
    web: {
      file: `${WEB_APP}/src/features/settings/components/settings-layout.tsx`,
      components: ["card", "field", "input", "select", "skeleton", "switch"],
      glue: [],
    },
    native: {
      file: `${NATIVE_APP}/src/components/settings-layout.tsx`,
      components: [
        "ActivityIndicator",
        "Pressable",
        "ScrollView",
        "Switch",
        "Text",
        "TextInput",
        "View",
      ],
      glue: [],
    },
  },
  ...(
    [
      [
        "members-table",
        "Members table",
        "organizations",
        "An organization's members with their roles and actions.",
      ],
      [
        "invite-dialog",
        "Invite dialog",
        "invitations",
        "A form that invites a teammate by email with a role.",
      ],
      [
        "api-keys-table",
        "API keys table",
        "api-keys",
        "The organization's API keys, with create and revoke.",
      ],
      [
        "audit-log-table",
        "Audit log table",
        "audit",
        "The audit trail with filters by actor and action.",
      ],
      [
        "tag-input",
        "Tag input",
        "tags",
        "An input that adds and removes tags on a record.",
      ],
    ] as const
  ).map(([slug, title, block, description]): RecipeSource => ({
    slug,
    title,
    block,
    description,
    hook: { name: "", entry: `better-supabase/blocks/${block}/react` },
    missing: `a client controller and React hook for the ${block} block (plan 003, workstream 4)`,
  })),
];

interface Snippet {
  readonly file: string;
  readonly code: string;
}

interface Recipe {
  readonly slug: string;
  readonly title: string;
  readonly block: string;
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
  readonly missing: string | null;
}

const REGION = /^\s*\/\/ #(region|endregion) recipe:([a-z0-9-]+)\s*$/;

/** The code between the recipe's region markers in `file`, regions joined in order. */
function extractRegion(source: string, slug: string, file = ""): string {
  const parts: string[] = [];
  let current: string[] | null = null;
  for (const line of source.split("\n")) {
    const marker = REGION.exec(line);
    if (marker?.[2] === slug) {
      if (marker[1] === "region") {
        if (current) throw new Error(`${file}: nested region recipe:${slug}`);
        current = [];
      } else {
        if (!current)
          throw new Error(`${file}: #endregion recipe:${slug} without #region`);
        parts.push(current.join("\n").trim());
        current = null;
      }
      continue;
    }
    if (marker) continue;
    current?.push(line);
  }
  if (current) throw new Error(`${file}: region recipe:${slug} is not closed`);
  if (parts.length === 0) throw new Error(`${file}: no region recipe:${slug}`);
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
      if (side)
        owners.set(side.file, [...(owners.get(side.file) ?? []), recipe.slug]);
    }
  }
  for (const file of [
    ...sourceFiles(`${WEB_APP}/src`),
    ...sourceFiles(`${NATIVE_APP}/src`),
  ]) {
    for (const line of readFileSync(join(ROOT, file), "utf8").split("\n")) {
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
  if (!side) return null;
  const source = readFileSync(join(ROOT, side.file), "utf8");
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
    const available = recipe.web !== undefined && recipe.native !== undefined;
    const screenshot = `${recipe.slug}.png`;
    return {
      slug: recipe.slug,
      title: recipe.title,
      block: recipe.block,
      description: recipe.description,
      status: available ? "available" : "planned",
      hook: available ? recipe.hook : null,
      web: withSnippet(recipe.web, recipe.slug),
      native: withSnippet(recipe.native, recipe.slug),
      screenshot:
        available && screenshots.has(screenshot)
          ? { src: `/recipes/${screenshot}`, ...pngSize(screenshot) }
          : null,
      missing: recipe.missing ?? null,
    };
  });
}

const fence = (language: string, code: string, title?: string): string =>
  `\`\`\`${language}${title ? ` title="${title}"` : ""}\n${code}\`\`\``;

/** One recipe as Markdown, shared by the docs page and the skill. */
function recipeMarkdown(recipe: Recipe, heading: string): string {
  if (!recipe.web || !recipe.native || !recipe.hook) return "";
  const lines = [
    `${heading} ${recipe.title}`,
    "",
    `${recipe.description} Both sides call \`${recipe.hook.name}\` from \`${recipe.hook.entry}\`; the [${recipe.block} block](${SITE}/blocks/${recipe.block}) must be installed (\`npx better-supabase sql add ${recipe.block}\`). Page: ${SITE}/recipes/${recipe.slug}.`,
    "",
    "Web, with shadcn components:",
    "",
    fence("bash", `npx shadcn add ${recipe.web.components.join(" ")}\n`),
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
  lines.push(
    "",
    fence("tsx", recipe.web.snippet.code, recipe.web.snippet.file),
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

function plannedTable(recipes: readonly Recipe[]): string {
  return table([
    ["Recipe", "Block", "Waits for"],
    ...recipes
      .filter((recipe) => recipe.status === "planned")
      .map((recipe) => [
        recipe.title,
        `\`${recipe.block}\``,
        recipe.missing ?? "",
      ]),
  ]);
}

const INTRO = `better-supabase ships no visible UI components. A recipe builds one interface from your own shadcn components (web) or React Native primitives (native) and a block's hook. The web and native code call the same hook, and both come from the example apps, \`apps/examples/nextjs\` and \`apps/examples/expo-powersync\`, so they typecheck and run.`;

function renderDocsPage(recipes: readonly Recipe[]): string {
  const available = recipes.filter((recipe) => recipe.status === "available");
  return [
    "---",
    "title: UI recipes",
    "description: Build notifications, search, onboarding, comments, an organization switcher, a plan picker, a usage meter, a feature gate and settings pages from shadcn or React Native components and the blocks' hooks.",
    "---",
    "",
    "{/* Generated by scripts/build-recipes.ts from the example apps. Edit the examples or the script, then run `pnpm recipes`. */}",
    "",
    INTRO,
    "",
    `Each recipe also has a page at [bettersupabase.com/recipes](${SITE}/recipes) with a screenshot. The native snippets use plain React Native primitives, so they run without a styling library; [React Native Reusables](https://reactnativereusables.com) serves shadcn-style native components from a working registry if you want them.`,
    "",
    ...available.flatMap((recipe) => [recipeMarkdown(recipe, "##"), ""]),
    "## Planned",
    "",
    plannedTable(recipes),
    "",
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
    "## Planned",
    "",
    "These have no hook yet. Build them from the block's TypeScript client in a server action or loader until the hook ships.",
    "",
    plannedTable(recipes),
    "",
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
      for (const [file, contents] of outputs) writeFileSync(file, contents);
    }
    if (argv.includes("--check")) {
      const stale = [...outputs]
        .filter(([file, contents]) => readFileSync(file, "utf8") !== contents)
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
