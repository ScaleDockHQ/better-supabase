import { describe, expect, it } from "vitest";

import type {
  PresetCatalog,
  PresetGlueItem,
} from "../../src/preset/catalog-types.ts";
import type { ResolvedPreset } from "../../src/preset/resolve.ts";

import {
  createUrl,
  presetApplyCommand,
  presetConfigSource,
  presetInstallCommand,
} from "../../src/preset/design.ts";
import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import { namedPreset } from "../../src/preset/presets.ts";
import {
  configSource,
  glueCommand,
  presetBlocksSource,
  presetGlue,
} from "../../src/preset/render.ts";
import { resolvePreset } from "../../src/preset/resolve.ts";

describe("presetConfigSource", () => {
  it("lists every block, with the reason for those it adds", async () => {
    const preset = {
      ...DEFAULT_CONVENTIONS,
      casing: "camel" as const,
      api: "api" as const,
      access: "provider" as const,
      adapters: ["next" as const],
      blocks: ["comments", "api-keys"],
    };

    const resolved = resolvePreset(preset);

    expect(await presetConfigSource(resolved)).toBe(
      [
        'import { defineConfig } from "better-supabase/config";',
        "",
        `// ${await createUrl(resolved)}`,
        "export default defineConfig({",
        '  database: { sql: { api: "api" } },',
        '  gen: { casing: "camel" },',
        '  adapters: ["next"],',
        "  // The provider access model reads roles from your authorization",
        "  // library: set `auth.authorization` to its adapter.",
        "  blocks: [",
        '    "updated-at", // required by memberships',
        '    "memberships", // required by api-keys, comments and messaging',
        '    { block: "permissions", model: "provider" }, // required by api-keys, comments, subjects and messaging',
        '    "api-keys",',
        '    "comments",',
        '    "subjects", // required by comments and messaging',
        '    "messaging", // required by comments',
        "  ],",
        "});",
        "",
      ].join("\n"),
    );
  });

  it("keeps a default preset short", async () => {
    const source = await presetConfigSource(
      resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: ["profiles"] }),
    );

    expect(source).toContain('  blocks: [\n    "profiles",\n  ],');
    expect(source).not.toContain("casing");
  });
});

describe("presetBlocksSource", () => {
  it("wires the blocks with a client through the generated config", () => {
    const source = presetBlocksSource(
      resolvePreset({
        ...DEFAULT_CONVENTIONS,
        api: "api",
        blocks: ["comments", "ai-chat"],
      }),
    );

    expect(source).toContain(
      'import { commentsBlock } from "better-supabase/blocks/comments";',
    );
    expect(source).toContain(
      'import { blockConfig } from "./supabase/blocks.generated";',
    );
    expect(source).toContain(
      "export const blockSet = defineBlocks(blockConfig, {",
    );
    expect(source).toContain("  aiChat: aiChatBlock,");
    expect(source).toContain(
      "return blockSet.create({ transport: rpcTransport(supabase) });",
    );
    // The API schema comes from blocks.generated.ts, not the wiring.
    expect(source).not.toContain("API_SCHEMA");
    // Blocks with only SQL (tenant, access) get no client.
    expect(source).not.toContain("membershipsBlock");
  });

  it("imports the generated config from the path it is given", () => {
    const source = presetBlocksSource(
      resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: ["tags"] }),
      "./db/blocks.generated.ts",
    );

    expect(source).toContain(
      'import { blockConfig } from "./db/blocks.generated.ts";',
    );
  });
});

describe("presetInstallCommand and presetApplyCommand", () => {
  it("start or apply a named preset by its name", async () => {
    const resolved = resolvePreset(namedPreset("crm"));

    expect(await presetInstallCommand(resolved)).toBe(
      "npx better-supabase init --preset crm",
    );
    expect(await presetApplyCommand(resolved)).toBe(
      "npx better-supabase add --preset crm",
    );
  });

  it("start or apply another preset by its /create URL", async () => {
    const resolved = resolvePreset({
      ...DEFAULT_CONVENTIONS,
      blocks: ["tags", "comments"],
    });

    const url = await createUrl(resolved);

    expect(url).toMatch(
      /^https:\/\/app\.bettersupabase\.com\/create\?design=0/,
    );
    expect(await presetInstallCommand(resolved)).toBe(
      `npx better-supabase init --preset "${url}"`,
    );
    expect(await presetApplyCommand(resolved)).toBe(
      `npx better-supabase add --preset "${url}"`,
    );
  });
});

const block = (name: string, selected = true) => ({
  name,
  title: name,
  category: "content" as const,
  selected,
  requiredBy: [],
  reason: selected ? "selected" : "required by notes",
});

// SAFETY: render reads only `preset`, `blocks` and `manifests`.
const resolvedWith = (fields: object) => fields as unknown as ResolvedPreset;

describe("configSource", () => {
  it("writes block entries as literals and appends blocks the preset doesn't list", () => {
    const source = configSource(
      resolvedWith({
        preset: { access: "rls" },
        blocks: [block("notes"), block("tags", false)],
      }),
      // SAFETY: configSource reads only the keys it groups.
      {
        casing: "camel",
        blocks: {
          notes: { block: "notes", options: {}, "title-key": ["a", 1] },
          tags: {},
          "team-notes": { block: "notes" },
        },
      } as never,
      "https://example.com/create",
    );

    expect(source.split("\n")).toEqual([
      'import { defineConfig } from "better-supabase/config";',
      "",
      "// https://example.com/create",
      "export default defineConfig({",
      '  gen: { casing: "camel" },',
      "  blocks: [",
      '    { block: "notes", options: {}, "title-key": ["a", 1] },',
      '    "tags", // required by notes',
      '    { block: "notes", name: "team-notes" },',
      "  ],",
      "});",
      "",
    ]);
  });
});

const manifest = (
  name: string,
  client: PresetCatalog["manifests"][number]["client"],
) => ({
  name,
  sql: [name],
  category: "content" as const,
  client,
  consumes: {},
  provides: [],
});

const catalogBlock = (name: string, manifestName = name) => ({
  name,
  title: name,
  category: "content" as const,
  requires: [],
  manifest: manifestName,
});

describe("presetBlocksSource with instances", () => {
  it("wires an instance under its own name and skips those without a client", () => {
    const catalog = {
      blocks: [catalogBlock("notes"), catalogBlock("audit")],
      manifests: [
        manifest("notes", { export: "notesBlock", subpath: "bs/notes" }),
        manifest("audit", null),
      ],
      glue: [],
    } as unknown as PresetCatalog;

    const source = presetBlocksSource(
      resolvedWith({
        preset: {
          instances: {
            "team-notes": { block: "notes" },
            notes: {},
            "audit-log": { block: "audit" },
            "ghost-block": { block: "ghost" },
          },
        },
        manifests: [],
      }),
      "./gen",
      catalog,
    );

    expect(source).toContain('import { notesBlock } from "bs/notes";');
    expect(source).toContain("  teamNotes: notesBlock,");
    expect(source).not.toContain("  notes: notesBlock,");
    expect(source).not.toContain("auditLog");
    expect(source).not.toContain("ghost");
  });
});

describe("presetGlue and glueCommand", () => {
  const item = (name: string, extra: Partial<PresetGlueItem> = {}) => ({
    name,
    title: name,
    blocks: ["notes"],
    frameworks: ["next"],
    platforms: ["web" as const],
    targets: ["~/app/notes.tsx"],
    ...extra,
  });

  const catalog = {
    blocks: [],
    manifests: [],
    glue: [
      item("notes-web"),
      item("notes-native", { platforms: ["native"] }),
      item("bundle", { preset: "starter" }),
      item("wiring", { targets: ["@lib/blocks.ts"] }),
      item("astro-notes", { frameworks: ["astro"] }),
      item("tags-web", { blocks: ["notes", "tags"] }),
    ],
  } as unknown as PresetCatalog;

  const glueFor = (platforms: string) =>
    presetGlue(
      resolvedWith({
        preset: { framework: "next", platforms },
        blocks: [block("notes")],
      }),
      catalog,
    ).map((each) => each.name);

  it("keeps items for the framework, platforms and installed blocks", () => {
    expect(glueFor("web")).toEqual(["notes-web"]);
    expect(glueFor("native")).toEqual(["notes-native"]);
    expect(glueFor("both")).toEqual(["notes-web", "notes-native"]);
  });

  it("names every item in one shadcn command", () => {
    expect(glueCommand([item("a"), item("b")])).toBe(
      "npx shadcn@latest add @better-supabase/a @better-supabase/b",
    );
  });
});
