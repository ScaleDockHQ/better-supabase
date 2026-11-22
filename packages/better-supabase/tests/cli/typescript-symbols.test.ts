import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { openSymbolTier } from "../../src/cli/typescript-symbols";

/** The only workspace that installs TypeScript 7.1 (ADR 1182). */
const ts71 = join(import.meta.dirname, "../../../../tests/types/ts-7.1");

describe("openSymbolTier", () => {
  it("returns a reason when typescript is not installed", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-symbols-"));
    const result = await openSymbolTier(root);

    expect(result.ok).toBe(false);
    expect(!result.ok && result.reason).toContain("not installed");
  });

  it("returns a reason below 7.1", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-symbols-"));
    const dir = join(root, "node_modules/typescript");

    await mkdir(dir, { recursive: true });
    await writeFile(
      join(dir, "package.json"),
      JSON.stringify({ name: "typescript", version: "6.0.3" }),
    );

    const result = await openSymbolTier(root);

    expect(result.ok).toBe(false);
    expect(!result.ok && result.reason).toContain("7.1");
  });

  it("follows a symbol across files with typescript 7.1", async () => {
    const project = await mkdtemp(join(tmpdir(), "bsb-symbols-"));

    await mkdir(join(project, "node_modules"), { recursive: true });
    await writeFile(
      join(project, "package.json"),
      JSON.stringify({ type: "module" }),
    );
    await writeFile(
      join(project, "tsconfig.json"),
      JSON.stringify({
        compilerOptions: { module: "esnext", target: "esnext" },
      }),
    );
    const a = join(project, "a.ts");
    const b = join(project, "b.ts");

    await writeFile(a, "export const answer = 42;\n");
    await writeFile(
      b,
      'import { answer } from "./a.ts";\nexport const twice = answer + answer;\n',
    );

    const result = await openSymbolTier(ts71);

    if (!result.ok) {
      throw new Error(result.reason);
    }

    try {
      const references = result.tier.references(a, "export const ".length + 1);
      const files = new Set(references.map((reference) => reference.file));

      expect(files.size).toBe(2);
      expect(references).toHaveLength(4);
      expect(
        references.every((reference) => reference.end - reference.start === 6),
      ).toBe(true);
      expect(
        result.tier
          .declaration(a, "export const ".length + 1)
          ?.file.toLowerCase(),
      ).toBe(a.toLowerCase());

      const importAt = "import { ".length + 1;
      const original = result.tier.declaration(b, importAt);

      expect(original?.file.toLowerCase()).toBe(a.toLowerCase());
      expect(
        result.tier
          .declaration(
            b,
            'import { answer } from "./a.ts";\nexport const twice = '.length +
              1,
          )
          ?.file.toLowerCase(),
      ).toBe(a.toLowerCase());
      expect(result.tier.typeOf(a, "export const ".length + 1)).toBe("42");
    } finally {
      result.tier.close();
    }
  });
});
