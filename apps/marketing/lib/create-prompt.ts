import {
  designApplyCommand,
  designInstallCommand,
  glueCommand,
  presetConfigSource,
  type PresetFramework,
  presetGlue,
  type ResolvedPreset,
} from "better-supabase/preset";

import {
  commandFor,
  CONFIG_FILE,
  type PackageManager,
  packagePath,
  withPackage,
} from "./create";
import {
  type AuthzLibrary,
  authzPromptSection,
  FRAMEWORKS,
  PLATFORM_LABELS,
} from "./create-options";
import { type AvailableRecipe, availableRecipes, shadcnAdd } from "./recipes";

/** One column of an app table, as the canvas designs it. */
export interface PromptDesignColumn {
  readonly type: string;
  readonly nullable?: boolean;
  readonly default?: string;
  readonly unique?: boolean;
  readonly references?: {
    readonly table: string;
    readonly block?: string;
    readonly onDelete?: string;
  };
}

/** One app table: `scope` and `timestamps` default to `"inherit"` and true. */
export interface PromptDesignTable {
  readonly columns?: Readonly<Record<string, PromptDesignColumn>>;
  readonly scope?: "inherit" | "user" | "none";
  readonly timestamps?: boolean;
}

/**
 * What the canvas adds on top of the preset: app tables, and extra columns
 * on block tables keyed by SQL module (`blocks.<module>.options.extraColumns`,
 * column name to SQL type). Structurally compatible with the library's
 * `CreateDesign`.
 */
export interface PromptDesign {
  readonly appTables?: Readonly<Record<string, PromptDesignTable>>;
  readonly extraColumns?: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
}

export interface CreatePromptInput {
  readonly resolved: ResolvedPreset;
  readonly design?: PromptDesign;
  /** Adds the screens: recipes, registry glue, routes and states. */
  readonly ui: boolean;
  readonly manager: PackageManager;
  /** The workspace package the app lives in, or undefined at the root. */
  readonly pkg: string | undefined;
  readonly authz: AuthzLibrary | undefined;
  /** The site origin, without a trailing slash. */
  readonly siteUrl: string;
  /** `init` for a new project, with `--package` already added. */
  readonly installCommand: string;
  /** `apply` for an existing project, with `--config` already added. */
  readonly applyCommand: string;
}

const WIRING_FILE = "lib/blocks.ts";

const MIGRATION_NAME = "better_supabase_blocks";

const ROUTERS = {
  next: "Use the App Router: a route group `app/(auth)` for the auth pages, and `app/(app)` with a `layout.tsx` that renders the app shell, so each page below is `app/(app)/<path>/page.tsx`.",
  vite: "Vite has no router of its own: add TanStack Router or React Router, with one layout route for the auth pages and one that renders the app shell.",
  "tanstack-start":
    "Use file routes in `src/routes`: a pathless layout route `_auth.tsx` for the auth pages and `_app.tsx` for the app shell, so each page below is `src/routes/_app/<path>.tsx`.",
  expo: "Use Expo Router: `app/(auth)` for the auth screens, and `app/(app)/_layout.tsx` with tabs or a drawer as the app shell, so each screen below is `app/(app)/<path>.tsx`.",
  sveltekit:
    "Use `src/routes/(auth)` for the auth pages and `src/routes/(app)/+layout.svelte` for the app shell, so each page below is `src/routes/(app)/<path>/+page.svelte`.",
  nuxt: "Use `pages/` with `layouts/auth.vue` for the auth pages and `layouts/default.vue` as the app shell, so each page below is `pages/<path>.vue`.",
  hono: "Hono serves the API only. Build these pages in the web or native client that calls it, and add a Hono route for each data call they make.",
  astro:
    "Use `src/pages` with `src/layouts/App.astro` as the app shell, so each page below is `src/pages/<path>.astro`, with the interactive parts as islands.",
  "react-router":
    "Declare the routes in `app/routes.ts`: one layout route for the auth pages and one for the app shell, with each page below in `app/routes/<path>.tsx`.",
} satisfies Readonly<Record<PresetFramework, string>>;

const code = (value: string): string => `\`${value}\``;

const unique = <T>(items: readonly T[]): T[] => [...new Set(items)];

const fence = (language: string, body: string): string =>
  [`\`\`\`${language}`, body.trimEnd(), "```"].join("\n");

const numbered = (steps: readonly string[]): string =>
  steps.map((step, index) => `${index + 1}. ${step}`).join("\n");

const bullets = (items: readonly string[]): string =>
  items.map((item) => `- ${item}`).join("\n");

const article = (word: string): string => (/^[aeiou]/u.test(word) ? "an" : "a");

const urlSegment = (table: string): string => table.replaceAll("_", "-");

/** The scope an app table ends up with: `inherit` follows the preset's. */
function tableScope(
  table: PromptDesignTable,
  resolved: ResolvedPreset,
): "tenant" | "user" | "none" {
  const scope = table.scope ?? "inherit";

  return scope === "inherit" ? resolved.preset.scope : scope;
}

function rlsNote(
  scope: "tenant" | "user" | "none",
  tenantName: string,
): string {
  switch (scope) {
    case "tenant": {
      return `Members of the row's ${tenantName} read and write it.`;
    }

    case "user": {
      return "Only the row's owner reads and writes it.";
    }

    case "none": {
      return "Signed-in users read every row; only the service role writes.";
    }

    default: {
      const unknown: never = scope;

      return unknown;
    }
  }
}

function columnLine(name: string, column: PromptDesignColumn): string {
  const parts = [`${code(name)} ${column.type}`];

  parts.push(column.nullable === true ? "nullable" : "not null");

  if (column.unique === true) {
    parts.push("unique");
  }

  if (column.default !== undefined) {
    parts.push(`default ${code(column.default)}`);
  }

  const { references } = column;

  if (references !== undefined) {
    const block =
      references.block === undefined
        ? ""
        : ` (the ${code(references.block)} block)`;

    const onDelete =
      references.onDelete === undefined
        ? ""
        : `, on delete ${references.onDelete}`;

    parts.push(
      `references ${code(`${references.table}.id`)}${block}${onDelete}`,
    );
  }

  return parts.join(", ");
}

function appTablesSection(
  tables: Readonly<Record<string, PromptDesignTable>>,
  resolved: ResolvedPreset,
): string {
  const { tenantName, idType } = resolved.preset;

  const described = Object.entries(tables).map(([name, table]) => {
    const scope = tableScope(table, resolved);

    const columns = [
      `${code("id")} uuid, primary key`,
      ...(scope === "tenant"
        ? [
            `${code(`${tenantName}_id`)} ${idType}, the ${tenantName} the row belongs to`,
          ]
        : []),
      ...(scope === "user"
        ? [`${code("user_id")} uuid, the user who owns the row`]
        : []),
      ...Object.entries(table.columns ?? {}).map(([column, info]) =>
        columnLine(column, info),
      ),
      ...(table.timestamps === false
        ? []
        : [
            `${code("created_at")} and ${code("updated_at")} timestamptz, set on insert and update`,
          ]),
    ];

    return [
      `### ${code(name)}`,
      bullets(columns),
      `RLS: ${rlsNote(scope, tenantName)}`,
    ].join("\n\n");
  });

  return [
    "## App tables",
    `Add these tables under \`appTables\` in ${code(CONFIG_FILE)}. \`sql sync\` writes them into \`supabase/schemas/\` with their indexes, foreign keys and RLS policies, so they follow the same access rules as the block tables. The \`id\`, scope and timestamp columns are implicit: don't list them.`,
    fence("ts", `appTables: ${JSON.stringify(tables, null, 2)},`),
    ...described,
  ].join("\n\n");
}

function extraColumnsSection(
  extra: Readonly<Record<string, Readonly<Record<string, string>>>>,
): string {
  const blocks = Object.fromEntries(
    Object.entries(extra).map(([module, columns]) => [
      module,
      { options: { extraColumns: columns } },
    ]),
  );

  return [
    "## Extra columns on block tables",
    `Merge these options into the matching entries of \`blocks\` in ${code(CONFIG_FILE)}, keeping the options an entry already has. Each column joins the block's table, so the block's RLS policies cover it.`,
    fence("ts", `blocks: ${JSON.stringify(blocks, null, 2)},`),
    bullets(
      Object.entries(extra).flatMap(([module, columns]) =>
        Object.entries(columns).map(
          ([column, type]) => `${code(module)}: ${code(column)} ${type}`,
        ),
      ),
    ),
  ].join("\n\n");
}

function recipesFor(resolved: ResolvedPreset): readonly AvailableRecipe[] {
  const installed = new Set([
    ...resolved.blocks.map((block) => block.name),
    ...resolved.manifests.map((manifest) => manifest.name),
  ]);

  const seen = new Set<string>();

  return availableRecipes.filter((recipe) => {
    if (!installed.has(recipe.block) || seen.has(recipe.slug)) {
      return false;
    }

    seen.add(recipe.slug);

    return true;
  });
}

function uiSection(
  input: CreatePromptInput,
  run: (command: string) => string,
): string {
  const { resolved, design, siteUrl } = input;
  const { framework, platforms, scope, tenantName } = resolved.preset;

  const sides: readonly ("web" | "native")[] =
    platforms === "both" ? ["web", "native"] : [platforms];

  const recipes = recipesFor(resolved);
  const glueItems = presetGlue(resolved);
  const glueNames = new Set(glueItems.map((item) => item.name));

  const webComponents = unique(
    recipes.flatMap((recipe) =>
      sides.includes("web") ? recipe.web.components : [],
    ),
  ).toSorted();

  const recipeGlue = unique(
    recipes.flatMap((recipe) => sides.flatMap((side) => recipe[side].glue)),
  ).filter((name) => !glueNames.has(name));

  const setup = [
    ...(webComponents.length > 0
      ? [
          `Add the shadcn components the recipes use: \`${run(shadcnAdd(webComponents))}\`.`,
        ]
      : []),
    ...(sides.includes("native")
      ? [
          "On native, the recipes use `react-native` primitives, so they need no extra UI library. Use the app's own components if it has them.",
        ]
      : []),
    ...(glueItems.length > 0
      ? [
          `Add the registry glue for ${FRAMEWORKS[framework].label}: \`${run(glueCommand(glueItems))}\`. The items are copied into the app, so edit them as needed.`,
        ]
      : []),
    ...(recipeGlue.length > 0
      ? [
          `Add the glue the recipes use: \`${run(shadcnAdd(recipeGlue, true))}\`.`,
        ]
      : []),
    ...(sides.includes("web")
      ? [
          `Add the ReUI data grid for the tables: \`${run("npx shadcn@latest add @reui/data-grid")}\`.`,
        ]
      : []),
  ];

  const appTables = Object.keys(design?.appTables ?? {});

  const pages = [
    "`/sign-in`, `/sign-up` and `/reset-password`: the auth pages, outside the app shell. Sign-in redirects to `/` and sign-out returns to `/sign-in`.",
    "`/`: the home page, with a summary of what the blocks hold.",
    ...appTables.flatMap((table) => [
      `\`/${urlSegment(table)}\`: the ${code(table)} rows in ${sides.includes("web") ? "a data grid" : "a list"}, with search, sorting and a New button.`,
      `\`/${urlSegment(table)}/new\` and \`/${urlSegment(table)}/:id\`: a form to create a row, and one to read, edit and delete it.`,
    ]),
    "`/settings`: the account and, where the blocks have them, the settings recipes.",
  ];

  const shell = [
    `The app shell has the navigation (a sidebar on web, tabs or a drawer on native) with a link to each page, and a user menu with sign-out.`,
    ...(scope === "tenant"
      ? [
          `Rows belong to ${article(tenantName)} ${tenantName}, so the shell has ${article(tenantName)} ${tenantName} switcher. Switching it changes which rows every page shows.`,
        ]
      : []),
  ];

  const crud =
    appTables.length === 0
      ? []
      : [
          `Each app table gets list, create, detail and edit screens. ${sides.includes("web") ? "On web, list the rows with the ReUI data grid (sorting, pagination, a row action menu). " : ""}${sides.includes("native") ? "On native, list them in a `FlatList`. " : ""}Read and write through the generated repository, so RLS decides what each user sees, and confirm deletes in a dialog.`,
        ];

  return [
    "## UI",
    `Build the screens for ${PLATFORM_LABELS[platforms].toLowerCase()} on ${FRAMEWORKS[framework].label}.`,
    "### Components and glue",
    numbered(
      setup.length > 0
        ? setup
        : ["The blocks need no extra components or glue."],
    ),
    "### Recipes",
    recipes.length === 0
      ? "No recipe covers these blocks yet. Build their screens from the block docs."
      : [
          "Each recipe is one screen or component for a block. Read it before you build that part, and adapt it to the app instead of copying it.",
          bullets(
            recipes.map(
              (recipe) =>
                `[${recipe.title}](${siteUrl}/recipes/${recipe.slug}.md): ${recipe.description} It calls ${code(recipe.hook.name)} from ${code(recipe.hook.entry)}.`,
            ),
          ),
        ].join("\n\n"),
    "### Routes and pages",
    ROUTERS[framework],
    `Write \`:id\` in the router's own syntax for a dynamic segment.`,
    bullets(pages),
    shell.join(" "),
    ...crud,
    "Place the recipes where they fit: the notification bell and the switchers in the shell, settings recipes under `/settings`, and the rest on the page of the data they show.",
    "### States",
    "Every screen that loads data has three states: a loading state with a skeleton in the layout of the content, an empty state with one action (for example New on a list), and an error state that says what failed with a Retry button.",
  ].join("\n\n");
}

/**
 * The instructions a coding agent follows to install the `/create`
 * selection: the install steps, the app tables and extra columns with
 * their RLS behavior, the authorization library's setup and the checks.
 * With `ui`, it adds the screens: the recipes for the installed blocks, the
 * registry glue, the route map for the framework and the states.
 */
export function createPrompt(input: CreatePromptInput): string {
  const { resolved, manager, pkg, authz, siteUrl } = input;
  const design = input.design ?? {};
  const { framework } = resolved.preset;

  const run = (command: string): string => commandFor(command, manager);

  const bs = (args: string): string =>
    run(
      `npx better-supabase ${args}${pkg === undefined ? "" : ` --cwd ${pkg}`}`,
    );

  const configFile = packagePath(CONFIG_FILE, pkg);
  const wiringFile = packagePath(WIRING_FILE, pkg);

  const appTables = design.appTables ?? {};
  const extraColumns = design.extraColumns ?? {};
  const hasTables = Object.keys(appTables).length > 0;
  const hasExtra = Object.keys(extraColumns).length > 0;

  const selected = resolved.blocks.filter((block) => block.selected);
  const required = resolved.blocks.filter((block) => !block.selected);

  const blocks = [
    `Selected: ${selected.map((block) => code(block.name)).join(", ") || "none"}.`,
    ...(required.length > 0
      ? [
          `Added because other blocks need them: ${required.map((block) => code(block.name)).join(", ")}.`,
        ]
      : []),
  ];

  const install = [
    `In a new project, run \`${run(input.installCommand)}\`. In a project that already has a better-supabase config, run \`${run(input.applyCommand)}\` instead. Either one writes ${code(configFile)}, ${code(wiringFile)} and the SQL module files in \`supabase/schemas/\`.`,
    ...(hasTables || hasExtra
      ? [
          `Edit ${code(configFile)} as the ${hasTables && hasExtra ? "app tables and extra columns sections below say" : `${hasTables ? "app tables" : "extra columns"} section below says`}.`,
        ]
      : []),
    `Write the SQL modules for the config: \`${bs("sql sync")}\`. Run it again after every config change.`,
    `Start the local stack with \`supabase start\`, then write its URL and keys to \`.env.local\`: \`${bs("env")}\`.`,
    `Create the migration from the schema files: \`supabase db schema declarative sync -f ${MIGRATION_NAME}\`. Then write the modules' rows and settings into a second migration: \`${bs("sql data")}\`.`,
    "Apply both migrations: `supabase migration up`.",
    `Generate the types, the models and \`supabase/blocks.generated.ts\`: \`${bs("gen")}\`.`,
    `Wire ${code(wiringFile)}: call \`blocks(supabase)\` with the signed-in user's Supabase client wherever the app calls a block, so RLS and each function's checks apply. Never pass a service-role client.`,
  ];

  const checks = [
    "The app typechecks (`tsc --noEmit`).",
    `\`${bs("doctor")}\` reports no errors, and \`${bs("gen --check")}\` reports no drift.`,
    `\`supabase test db\` passes: the pgTAP tests check RLS on every block table.${hasTables ? " Add a pgTAP test for each app table that signs in as a user who may read a row and as one who may not." : ""}`,
  ];

  const authzSection =
    authz === undefined
      ? []
      : [authzPromptSection(authz, manager, pkg, presetConfigSource(resolved))];

  return [
    `# Install better-supabase: ${resolved.blocks.length} blocks on ${FRAMEWORKS[framework].label}`,
    `Set up better-supabase in this app with the blocks below, then run the checks at the end. When a step is unclear, read the docs at ${siteUrl}/docs.`,
    "## Blocks",
    bullets(blocks),
    "## Install",
    numbered(install),
    ...(hasTables ? [appTablesSection(appTables, resolved)] : []),
    ...(hasExtra ? [extraColumnsSection(extraColumns)] : []),
    ...authzSection,
    ...(input.ui ? [uiSection({ ...input, design }, run)] : []),
    "## Checks",
    bullets(checks),
  ]
    .join("\n\n")
    .concat("\n");
}

/**
 * `createPrompt` with the init and apply commands for the preset and its
 * design (`designCode`, empty without one), moved into `pkg` in a monorepo.
 */
export function presetPrompt(
  input: Omit<CreatePromptInput, "installCommand" | "applyCommand"> & {
    readonly designCode?: string;
  },
): string {
  const { designCode = "", ...rest } = input;

  return createPrompt({
    ...rest,
    installCommand: withPackage(
      designInstallCommand(input.resolved, designCode),
      input.pkg,
    ),
    applyCommand: withPackage(
      designApplyCommand(input.resolved, designCode),
      input.pkg,
    ),
  });
}
