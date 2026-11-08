import { describe, expect, it } from "vitest";

import { emitHooks } from "../../src/cli/gen/hooks.ts";
import { baseFiles } from "../../src/cli/templates.ts";
import { resolveConfig } from "../../src/config/resolve.ts";
import * as plugins from "../../src/plugins/index.ts";

const { defineFramework, frameworkRegistry, BUILT_IN_FRAMEWORKS } = plugins;

const qwik = defineFramework({
  name: "qwik",
  tier: "community",
  detect: ["@builder.io/qwik"],
  hooksModule: "@acme/qwik-hooks",
  hooksDirective: '"use qwik";',
});

describe("defineFramework", () => {
  it("builds a binding at the current contract", () => {
    expect(qwik.apiVersion).toBe(plugins.FRAMEWORK_API_VERSION);
    expect(plugins.hooksSubpathOf(qwik)).toBe("qwik");
    expect(
      plugins.hooksSubpathOf(
        defineFramework({
          name: "x",
          tier: "supported",
          detect: ["x"],
          hooksSubpath: "xx",
        }),
      ),
    ).toBe("xx");
  });

  it.each([
    [{ name: "Bad", tier: "community", detect: ["x"] }, "lowercase letters"],
    [{ name: "ok", tier: "other", detect: ["x"] }, "needs a `tier`"],
    [{ name: "ok", tier: "community", detect: [] }, "needs `detect`"],
  ])("refuses %j", (definition, message) => {
    expect(() => defineFramework(definition as never)).toThrow(message);
  });

  it("names the contract an old or foreign binding targets", () => {
    expect(plugins.frameworkProblem(null)).toContain("is an object");
    expect(plugins.frameworkProblem({})).toContain("needs a `name`");
    expect(plugins.frameworkProblem({ name: 1 })).toContain("needs a `name`");
    expect(
      plugins.frameworkProblem({ name: "x", tier: "community", detect: ["x"] }),
    ).toContain("targets framework API none");
    expect(
      plugins.frameworkProblem({
        apiVersion: 2,
        name: "x",
        tier: "community",
        detect: ["x"],
      }),
    ).toContain("targets framework API 2");
  });
});

describe("frameworkRegistry", () => {
  it("lists the built-in bindings and detects them from packages", () => {
    const registry = frameworkRegistry();

    expect(registry.names).toEqual(["react", "svelte", "vue", "solid"]);
    expect(registry.detect({ "solid-js": "1" })?.name).toBe("solid");
    expect(registry.detect({ express: "5" })).toBeUndefined();
    expect(registry.get("react")?.tier).toBe("supported");
    expect(registry.get("nope")).toBeUndefined();
  });

  it("selects react for the adapters that imply it", () => {
    const registry = frameworkRegistry();

    expect(registry.forIntegrations(["hono", "next"])?.name).toBe("react");
    expect(registry.forIntegrations(["expo"])?.name).toBe("react");
    expect(registry.forIntegrations(["hono"])).toBeUndefined();
  });

  it("adds a third-party binding and refuses duplicates and bad ones", () => {
    expect(frameworkRegistry([qwik]).detect({ "@builder.io/qwik": "1" })).toBe(
      qwik,
    );
    const resolved = frameworkRegistry([qwik]).bindings;
    expect(frameworkRegistry(resolved).names).toEqual(
      resolved.map((b) => b.name),
    );
    expect(() => frameworkRegistry([qwik, { ...qwik }])).toThrow(
      'framework "qwik" is already registered',
    );
    expect(() =>
      frameworkRegistry([{ ...BUILT_IN_FRAMEWORKS[0]!, name: "vue" }]),
    ).toThrow('framework "vue" is already registered');
    expect(() => frameworkRegistry([{ name: "X" } as never])).toThrow(
      "lowercase letters",
    );
  });
});

describe("gen.hooks with a registered framework", () => {
  const config = resolveConfig(
    { gen: { frameworks: [qwik], hooks: "qwik" } },
    "/project",
  );

  it("resolves the name and keeps the registry on the config", () => {
    expect(config.hooks).toBe("qwik");
    expect(config.frameworks.map((binding) => binding.name)).toEqual([
      "react",
      "svelte",
      "vue",
      "solid",
      "qwik",
    ]);
  });

  it("writes hooks.ts from the binding's module and directive", () => {
    const contents = emitHooks(config, ["notes"])?.contents ?? "";

    expect(contents).toContain('"use qwik";');
    expect(contents).toContain(
      'import { defineListHook, defineOneHook } from "@acme/qwik-hooks";',
    );
    expect(contents).not.toContain('"use client";');
  });

  it("refuses a name nothing registers, listing what is registered", () => {
    expect(() => resolveConfig({ gen: { hooks: "qwik" } }, "/project")).toThrow(
      'gen.hooks names framework "qwik", which nothing registers; the registered frameworks are react, svelte, vue, solid',
    );
    expect(() =>
      resolveConfig({ gen: { hooks: { framework: "nope" } } }, "/project"),
    ).toThrow('framework "nope"');
  });

  it("keeps the default, and false, without registration", () => {
    expect(resolveConfig({ adapters: ["next"] }, "/p").hooks).toBe("react");
    expect(resolveConfig({ adapters: ["hono"] }, "/p").hooks).toBe(false);
    expect(resolveConfig({ gen: { hooks: false } }, "/p").hooks).toBe(false);
  });

  it("writes no hooks without tables", () => {
    expect(emitHooks(config, [])).toBeUndefined();
  });

  it("refuses emitting for a name missing from the registry", () => {
    expect(() =>
      emitHooks({ hooks: "qwik", output: "src/g.ts" }, ["notes"]),
    ).toThrow("is not registered");
  });
});

describe("init", () => {
  const context = {
    srcDir: "src",
    generated: "src/lib/supabase/generated.ts",
    tsExtensions: false,
    frameworks: [],
    version: "0.0.0",
  } as const;

  it("writes gen.hooks for a framework no adapter selects", () => {
    const [config] = baseFiles(
      context,
      "snake",
      false,
      [],
      "pg-delta",
      undefined,
      { hooks: "qwik" },
    );

    expect(config?.contents).toContain(
      "gen: { casing: 'snake', output: 'src/lib/supabase/generated.ts', hooks: 'qwik' }",
    );

    const [plain] = baseFiles(context, "snake", false);
    expect(plain?.contents).not.toContain("hooks:");
  });
});

describe("serverSubpath and templates", () => {
  const binding = defineFramework({
    name: "qwik",
    tier: "community",
    detect: ["@builder.io/qwik"],
    serverSubpath: "qwik-server",
    templates: (context) => [
      {
        path: `${context.srcDir}/lib/qwik.ts`,
        contents: `import { handler } from '${context.serverImport}';\n`,
      },
    ],
  });

  const context = {
    srcDir: "src",
    generated: "src/g.ts",
    tsExtensions: false,
  } as const;

  it("names the server adapter import", () => {
    expect(plugins.serverImportOf(binding)).toBe("better-supabase/qwik-server");
    expect(plugins.serverImportOf(qwik)).toBeUndefined();
  });

  it("hands the templates the context and the server import", () => {
    expect(plugins.frameworkFiles(binding, context)).toEqual([
      {
        path: "src/lib/qwik.ts",
        contents: "import { handler } from 'better-supabase/qwik-server';\n",
      },
    ]);
    expect(plugins.frameworkFiles(qwik, context)).toEqual([]);
  });
});
