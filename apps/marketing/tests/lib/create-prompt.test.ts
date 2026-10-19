import {
  glueCommand,
  namedPreset,
  presetApplyCommand,
  presetConfigSource,
  presetGlue,
  presetInstallCommand,
  type ResolvedPreset,
  resolvePreset,
} from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import { commandFor, withPackage } from "../../lib/create";
import {
  AUTHZ_LIBRARIES,
  authzPromptSection,
  withAuthChoice,
} from "../../lib/create-options";
import {
  createPrompt,
  type CreatePromptInput,
  type PromptDesign,
  screensCommands,
} from "../../lib/create-prompt";
import { availableRecipes } from "../../lib/recipes";

const SITE = "https://example.com";

function input(
  resolved: ResolvedPreset,
  overrides: Partial<CreatePromptInput> = {},
): CreatePromptInput {
  const pkg = overrides.pkg;

  return {
    resolved,
    ui: false,
    manager: "pnpm",
    pkg,
    authz: undefined,
    siteUrl: SITE,
    installCommand: withPackage(presetInstallCommand(resolved), pkg),
    applyCommand: withPackage(presetApplyCommand(resolved), pkg),
    ...overrides,
  };
}

const saas = resolvePreset(namedPreset("saas"));

const design: PromptDesign = {
  appTables: {
    projects: {
      columns: {
        name: { type: "text", unique: true },
        budget: { type: "bigint", nullable: true, default: "0" },
        owner_profile: {
          type: "uuid",
          references: {
            table: "profiles",
            block: "profiles",
            onDelete: "cascade",
          },
        },
      },
    },
    notes: { scope: "user", timestamps: false },
    changelog: { scope: "none" },
  },
  extraColumns: { comments: { mood: "text" } },
};

describe("createPrompt", () => {
  test("lists the install steps in the package manager's runner", () => {
    const prompt = createPrompt(input(saas));

    expect(prompt).toContain(
      `\`${commandFor(presetInstallCommand(saas), "pnpm")}\``,
    );
    expect(prompt).toContain(
      `\`${commandFor(presetApplyCommand(saas), "pnpm")}\``,
    );
    expect(prompt).toContain("`pnpm dlx better-supabase sql sync`");
    expect(prompt).toContain("supabase db schema declarative sync -f");
    expect(prompt).toContain("`pnpm dlx better-supabase sql data`");
    expect(prompt).toContain("`supabase migration up`");
    expect(prompt).toContain("`pnpm dlx better-supabase gen`");
    expect(prompt).toContain("`pnpm dlx better-supabase doctor`");
    expect(prompt).toContain("`supabase test db`");
    expect(prompt).toContain("`lib/blocks.ts`");
    expect(prompt).not.toContain("npx ");
    expect(prompt.endsWith("\n")).toBe(true);
  });

  test("without UI it has no screens", () => {
    const prompt = createPrompt(input(saas));

    expect(prompt).not.toContain("## UI");
    expect(prompt).not.toContain("/recipes/");
  });

  test("with UI it adds the recipes, the glue, the routes and the states", () => {
    const prompt = createPrompt(input(saas, { ui: true, design }));
    const installed = new Set(saas.blocks.map((block) => block.name));

    expect(prompt).toContain("## UI");

    for (const recipe of availableRecipes.filter((each) =>
      installed.has(each.block),
    )) {
      expect(prompt).toContain(`${SITE}/recipes/${recipe.slug}.md`);
    }

    const glue = presetGlue(saas);

    expect(glue.length).toBeGreaterThan(0);
    expect(prompt).toContain(commandFor(glueCommand(glue), "pnpm"));

    expect(prompt).toContain("`app/(auth)`");
    expect(prompt).toContain("`/sign-in`");
    expect(prompt).toContain("organization switcher");
    expect(prompt).toContain("`/projects/:id`");
    expect(prompt).toContain("@reui/data-grid");
    expect(prompt).toContain("Retry");
  });

  test("each recipe and each shadcn component appears once", () => {
    const prompt = createPrompt(
      input(resolvePreset(namedPreset("everything")), { ui: true }),
    );

    for (const recipe of availableRecipes) {
      expect(prompt.split(`/recipes/${recipe.slug}.md`)).toHaveLength(2);
    }

    const add = /pnpm dlx shadcn add ([^`]+)`/u.exec(prompt)?.[1] ?? "";
    const components = add.split(" ");

    expect(components.length).toBeGreaterThan(1);
    expect(new Set(components).size).toBe(components.length);
  });

  test("a native app gets Expo routes and lists instead of the data grid", () => {
    const expo = resolvePreset({
      ...namedPreset("saas"),
      framework: "expo",
      platforms: "native",
    });

    const prompt = createPrompt(input(expo, { ui: true, design }));

    expect(prompt).toContain("Expo Router");
    expect(prompt).toContain("`FlatList`");
    expect(prompt).not.toContain("@reui/data-grid");
    expect(prompt).not.toContain("scaffold screens");
  });

  test("Next.js app tables start from scaffold screens and the record recipes", () => {
    const prompt = createPrompt(input(saas, { ui: true, design }));

    expect(prompt).toContain(
      "pnpm dlx better-supabase scaffold screens projects",
    );
    expect(prompt).toContain("pnpm dlx better-supabase scaffold screens notes");
    expect(prompt).not.toContain("scaffold screens changelog");
    expect(prompt).toContain(`${SITE}/recipes/record-grid.md`);
  });

  test("screensCommands runs in the package and skips tables only the service role writes", () => {
    expect(screensCommands(design.appTables ?? {}, saas, "apps/web")).toEqual([
      "npx better-supabase scaffold screens projects --cwd apps/web",
      "npx better-supabase scaffold screens notes --cwd apps/web",
    ]);
  });

  test("app tables list their implicit columns and RLS by scope", () => {
    const prompt = createPrompt(input(saas, { design }));

    expect(prompt).toContain("## App tables");
    expect(prompt).toContain("appTables: {");
    expect(prompt).toContain("`organization_id` uuid");
    expect(prompt).toContain("`name` text, not null, unique");
    expect(prompt).toContain("`budget` bigint, nullable, default `0`");
    expect(prompt).toContain(
      "references `profiles.id` (the `profiles` block), on delete cascade",
    );
    expect(prompt).toContain(
      "Members of the row's organization read and write it.",
    );
    expect(prompt).toContain("`user_id` uuid, the user who owns the row");
    expect(prompt).toContain("Only the row's owner reads and writes it.");
    expect(prompt).toContain("only the service role writes");
    expect(prompt.split("`created_at` and `updated_at`")).toHaveLength(3);
  });

  test("extra columns go into the block's options", () => {
    const prompt = createPrompt(input(saas, { design }));

    expect(prompt).toContain("## Extra columns on block tables");
    expect(prompt).toContain('"extraColumns": {');
    expect(prompt).toContain("`comments`: `mood` text");
  });

  test("without a design there are no app tables or extra columns", () => {
    const prompt = createPrompt(input(saas));

    expect(prompt).not.toContain("## App tables");
    expect(prompt).not.toContain("## Extra columns");
  });

  test("an authorization library adds its setup", () => {
    const [authz] = AUTHZ_LIBRARIES;

    const provider = resolvePreset(
      withAuthChoice(namedPreset("saas"), "provider").preset,
    );

    const prompt = createPrompt(input(provider, { authz, manager: "npm" }));

    expect(prompt).toContain(
      authzPromptSection(authz, "npm", undefined, presetConfigSource(provider)),
    );
  });

  test("a monorepo package scopes the files and the CLI commands", () => {
    const prompt = createPrompt(
      input(saas, { pkg: "apps/web", manager: "bun" }),
    );

    expect(prompt).toContain("--package apps/web");
    expect(prompt).toContain("--config apps/web/better-supabase.config.ts");
    expect(prompt).toContain("`apps/web/better-supabase.config.ts`");
    expect(prompt).toContain("`apps/web/lib/blocks.ts`");
    expect(prompt).toContain("`bunx better-supabase sql sync --cwd apps/web`");
    expect(prompt).toContain("`bunx better-supabase gen --cwd apps/web`");
  });
});
