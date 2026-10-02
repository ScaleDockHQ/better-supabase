import { describe, expect, it } from "vitest";

import {
  baseFiles,
  INTEGRATIONS,
  isIntegration,
  needsLib,
  resolveIntegrations,
  suggestedIntegrations,
  type TemplateContext,
  TEMPLATES,
} from "../../src/cli/templates.ts";

const context = (
  overrides: Partial<TemplateContext> = {},
): TemplateContext => ({
  srcDir: "src",
  generated: "src/generated/supabase.ts",
  tsExtensions: false,
  frameworks: [],
  version: "1.2.3",
  ...overrides,
});

const contents = (files: { path: string; contents: string }[], path: string) =>
  files.find((file) => file.path === path)?.contents ?? "";

describe("public env per framework", () => {
  it.each([
    [["next"], "process.env.NEXT_PUBLIC_SUPABASE_URL!"],
    [["expo"], "process.env.EXPO_PUBLIC_SUPABASE_URL!"],
    [["vite"], "import.meta.env.VITE_SUPABASE_URL"],
    [[], "process.env.SUPABASE_URL!"],
  ] as const)("%j reads %s", (frameworks, url) => {
    const files = TEMPLATES.client.files(context({ frameworks }));
    expect(contents(files, "src/lib/supabase.browser.ts")).toContain(
      `url: ${url},`,
    );
  });
});

describe("import paths", () => {
  it("drops .ts unless the project keeps it, and adds ./ for siblings", () => {
    const [config, lib] = baseFiles(
      context({ generated: "src/lib/generated.ts" }),
      "camel",
    );
    expect(config!.contents).toContain("casing: 'camel'");
    expect(lib!.contents).toContain("from './generated';");
    const [, kept] = baseFiles(
      context({ generated: "src/lib/generated.ts", tsExtensions: true }),
      "snake",
    );
    expect(kept!.contents).toContain("from './generated.ts';");
  });

  it("writes only the config without the lib", () => {
    expect(baseFiles(context(), "snake", false).map((f) => f.path)).toEqual([
      "better-supabase.config.ts",
    ]);
  });

  it("keeps .ts in Edge Functions and pins the version in deno.json", () => {
    const files = TEMPLATES.edge.files(context({ srcDir: "." }));
    expect(contents(files, "supabase/functions/_shared/supabase.ts")).toContain(
      "from '../../../src/generated/supabase.ts';",
    );
    expect(
      JSON.parse(contents(files, "supabase/functions/api/deno.json")),
    ).toMatchObject({
      imports: { "better-supabase": "npm:better-supabase@^1.2.3" },
    });
    expect(TEMPLATES.mcp.files(context()).map((file) => file.path)).toEqual([
      "supabase/functions/_shared/supabase.ts",
      "supabase/functions/mcp/index.ts",
      "supabase/functions/mcp/deno.json",
    ]);
  });

  it("puts the React providers in app/ for Next.js", () => {
    expect(
      TEMPLATES.react.files(context({ frameworks: ["next"] }))[0],
    ).toMatchObject({
      path: "src/app/providers.tsx",
      contents: expect.stringMatching(/^'use client';/),
    });
    expect(TEMPLATES.react.files(context({ srcDir: "." }))[0]).toMatchObject({
      path: "providers.tsx",
      contents: expect.stringMatching(/^import /),
    });
  });

  it("imports the lib from the server templates", () => {
    expect(
      contents(TEMPLATES.hono.files(context()), "src/server.ts"),
    ).toContain("sb } from './lib/supabase';");
    expect(
      contents(TEMPLATES.orpc.files(context()), "src/router.ts"),
    ).toContain("import { sb } from './lib/supabase';");
    const next = TEMPLATES.next.files(context());
    expect(contents(next, "src/lib/supabase.server.ts")).toContain(
      "import { sb } from './supabase';",
    );
    expect(contents(next, "src/proxy.ts")).toContain(
      "import { next } from './lib/supabase.server';",
    );
  });
});

describe("integration lists", () => {
  it("adds dependencies first, once", () => {
    expect(resolveIntegrations(["react", "next", "client"])).toEqual([
      "client",
      "react",
      "next",
    ]);
  });

  it("suggests integrations for every detected framework", () => {
    expect(
      suggestedIntegrations([
        "next",
        "hono",
        "orpc",
        "vite",
        "expo",
        "tanstack-query",
      ]),
    ).toEqual(["client", "next", "hono", "orpc", "react"]);
    expect(suggestedIntegrations([])).toEqual([]);
  });

  it("rejects an unknown framework", () => {
    // SAFETY: simulates a framework value from a newer project file.
    const unknown = ["svelte"] as unknown as Parameters<
      typeof suggestedIntegrations
    >[0];
    expect(() => suggestedIntegrations(unknown)).toThrow(
      "Unknown framework svelte",
    );
  });

  it("knows the integration names and which need the lib", () => {
    expect(INTEGRATIONS.every(isIntegration)).toBe(true);
    expect(isIntegration("rails")).toBe(false);
    expect(needsLib([])).toBe(true);
    expect(needsLib(["edge", "mcp"])).toBe(false);
    expect(needsLib(["edge", "hono"])).toBe(true);
  });
});
