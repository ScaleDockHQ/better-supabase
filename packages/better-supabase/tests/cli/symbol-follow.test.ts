import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { ProjectSymbols } from "../../src/cli/typescript-symbols";

import { withoutColumnEntries } from "../../src/cli/codemod-config.ts";
import { withoutOptionKeys } from "../../src/cli/codemod-extra-columns.ts";
import { withoutConfigPaths } from "../../src/cli/codemod-prune.ts";
import {
  applySplices,
  followReexports,
  reexportsIn,
} from "../../src/cli/codemod-reexports.ts";
import {
  ConfigDocument,
  importedValues,
} from "../../src/cli/config-document/index.ts";
import { openSymbolTier } from "../../src/cli/typescript-symbols";

/** The only workspace that installs TypeScript 7.1 (ADR 1187). */
const ts71 = join(import.meta.dirname, "../../../../tests/types/ts-7.1");

const off: ProjectSymbols = { skipped: "typescript is not installed" };

async function project(files: Record<string, string>): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "bsb-follow-"));

  await mkdir(join(root, "node_modules"), { recursive: true });
  await writeFile(join(root, "package.json"), '{"type":"module"}');
  await writeFile(
    join(root, "tsconfig.json"),
    JSON.stringify({ compilerOptions: { module: "esnext", target: "esnext" } }),
  );

  for (const [name, text] of Object.entries(files)) {
    await writeFile(join(root, name), text);
  }

  return root;
}

const RENAMES = { oldName: "newName" };

describe("reexportsIn", () => {
  it("finds an unaliased re-export of a renamed name", () => {
    const text = [
      'export { oldName, other } from "better-supabase";',
      'export { oldName as alias } from "better-supabase";',
      'export { oldName } from "elsewhere";',
    ].join("\r\n");

    const found = reexportsIn("barrel.ts", text, RENAMES);

    expect(found).toEqual([
      { file: "barrel.ts", offset: 9, from: "oldName", to: "newName" },
    ]);
  });
});

describe("followReexports", () => {
  const barrel = 'export { oldName } from "better-supabase";\n';
  const page = 'import { oldName } from "./barrel.ts";\noldName();\n';

  const texts = new Map([
    ["barrel.ts", barrel],
    ["page.ts", page],
  ]);

  it("reports the files it did not follow when the tier is off", () => {
    const [reexport] = reexportsIn("barrel.ts", barrel, RENAMES);

    const result = followReexports([reexport!], off, [], (file) =>
      texts.get(file),
    );

    expect(result.splices.size).toBe(0);
    expect(result.review.get("barrel.ts")?.[0]?.message).toContain(
      "typescript is not installed",
    );
  });

  it("renames every reference in the other files", () => {
    const [reexport] = reexportsIn("barrel.ts", barrel, RENAMES);

    const tier: ProjectSymbols = {
      root: "/app",
      tier: {
        version: "7.1.0",
        references: () => [
          { file: "barrel.ts", start: 9, end: 16 },
          { file: "page.ts", start: 9, end: 16 },
          { file: "page.ts", start: 39, end: 46 },
        ],
        declaration: () => undefined,
        typeOf: () => undefined,
        close: () => {},
      },
    };

    const result = followReexports(
      [reexport!],
      tier,
      ["barrel.ts", "page.ts"],
      (file) => texts.get(file),
    );

    expect(applySplices(page, result.splices.get("page.ts") ?? [])).toBe(
      'import { newName } from "./barrel.ts";\nnewName();\n',
    );
    expect(result.splices.has("barrel.ts")).toBe(false);
  });

  it("follows a re-export through a real project with typescript 7.1", async () => {
    const root = await project({
      "barrel.ts": barrel.replace("better-supabase", "./lib.ts"),
      "lib.ts": "export const oldName = 1;\n",
      "page.ts": page,
    });

    const opened = await openSymbolTier(ts71);

    if (!opened.ok) {
      throw new Error(opened.reason);
    }

    try {
      const file = (name: string): string => join(root, name);
      const text = barrel.replace("better-supabase", "./lib.ts");

      const result = followReexports(
        [
          {
            file: file("barrel.ts"),
            offset: 9,
            from: "oldName",
            to: "newName",
          },
        ],
        { tier: opened.tier, root },
        [file("barrel.ts"), file("page.ts")],
        (name) =>
          name === file("barrel.ts")
            ? text
            : name === file("page.ts")
              ? page
              : undefined,
      );

      expect(
        applySplices(page, result.splices.get(file("page.ts")) ?? []),
      ).toBe('import { newName } from "./barrel.ts";\nnewName();\n');
      expect(result.splices.has(file("barrel.ts"))).toBe(false);
    } finally {
      opened.tier.close();
    }
  });
});

describe("withoutColumnEntries across files", () => {
  const config =
    'import { shared } from "./shared.ts";\nexport default defineConfig({ blocks: shared });\n';

  const shared =
    'export const shared = {\n  teams: { columns: { teams: { tenant: "org_id" } } },\n};\n';

  const entries = [
    { block: "teams", table: "teams", column: "tenant", why: "test" },
  ];

  it("reports the imported file when the tier is off", () => {
    const result = withoutColumnEntries(config, entries, {
      symbols: off,
      configFile: "/app/config.ts",
    });

    expect(result.text).toBe(config);
    expect(result.others).toEqual([]);
    expect(result.review.join("\n")).toContain("typescript is not installed");
    expect(result.review.join("\n")).toContain("blocks.teams.columns");
  });

  it("lists the imported names of a config", () => {
    expect(importedValues(ConfigDocument.parse(config))).toEqual([
      {
        name: "shared",
        offset: config.indexOf("shared });"),
        path: ["blocks"],
      },
    ]);
  });

  it("edits the file that declares the value", async () => {
    const root = await project({ "shared.ts": shared });
    const file = join(root, "shared.ts");
    const start = shared.indexOf("export");

    const symbols: ProjectSymbols = {
      root,
      tier: {
        version: "7.1.0",
        references: () => [],
        declaration: () => ({ file, start, end: shared.length }),
        typeOf: () => undefined,
        close: () => {},
      },
    };

    const result = withoutColumnEntries(config, entries, {
      symbols,
      configFile: join(root, "config.ts"),
    });

    expect(result.text).toBe(config);
    expect(result.others).toHaveLength(1);
    expect(result.others[0]?.file).toBe(file);
    expect(result.others[0]?.text).not.toContain("tenant");
    expect(result.review).toEqual([]);
  });
});

describe("the other config edits across files", () => {
  const config =
    'import { shared } from "./shared.ts";\nexport default defineConfig({ blocks: shared });\n';

  const shared =
    'export const shared = {\n  teams: { columns: { teams: { tenant: "org_id" } }, options: { extraColumns: { a: "text" }, keep: 1 } },\n};\n';

  const stub = async (): Promise<{
    follow: { symbols: ProjectSymbols; configFile: string };
    file: string;
  }> => {
    const root = await project({ "shared.ts": shared });
    const file = join(root, "shared.ts");

    return {
      file,
      follow: {
        configFile: join(root, "config.ts"),
        symbols: {
          root,
          tier: {
            version: "7.1.0",
            references: () => [],
            declaration: () => ({
              file,
              start: shared.indexOf("export"),
              end: shared.length,
            }),
            typeOf: () => undefined,
            close: () => {},
          },
        },
      },
    };
  };

  it("prunes a path from the file that declares the value", async () => {
    const { follow, file } = await stub();

    const result = withoutConfigPaths(
      config,
      ["blocks.teams.columns.teams.tenant"],
      follow,
    );

    expect(result.missed).toEqual([]);
    expect(result.text).toBe(config);
    expect(result.others.map((other) => other.file)).toEqual([file]);
    expect(result.others[0]?.text).not.toContain("tenant");
    expect(result.others[0]?.text).not.toContain("columns");
  });

  it("misses the path without the tier, as before", () => {
    const result = withoutConfigPaths(config, [
      "blocks.teams.columns.teams.tenant",
    ]);

    expect(result.missed).toEqual(["blocks.teams.columns.teams.tenant"]);
    expect(result.others).toEqual([]);
  });

  it("drops an option key from the file that declares the block", async () => {
    const { follow, file } = await stub();

    const result = withoutOptionKeys(
      config,
      new Set(["extraColumns"]),
      follow,
      ["teams"],
    );

    expect(result.others.map((other) => other.file)).toEqual([file]);
    expect(result.others[0]?.text).not.toContain("extraColumns");
    expect(result.others[0]?.text).toContain("keep: 1");
  });
});
