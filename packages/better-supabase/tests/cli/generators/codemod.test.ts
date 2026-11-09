import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../../src/cli/codemod.ts";
import {
  generatorsCodemod,
  moveGeneratorImports,
} from "../../../src/cli/generators/codemod.ts";

describe("codemod generators", () => {
  it("is registered", () => {
    expect(CODEMODS["generators"]?.name).toBe("generators");
  });

  it("moves each generator to its subpath and keeps the rest", () => {
    const text = `import { defineConfig, jsonSchema, valibot, zod } from "better-supabase/config";\n`;

    expect(moveGeneratorImports(text)).toBe(
      [
        `import { defineConfig } from "better-supabase/config";`,
        `import { jsonSchema } from "better-supabase/generators/json-schema";`,
        `import { valibot } from "better-supabase/generators/valibot";`,
        `import { zod } from "better-supabase/generators/zod";`,
        "",
      ].join("\n"),
    );
  });

  it("groups names of one generator and keeps type imports and aliases", () => {
    const text = `import type { JsonSchemaTarget, ZodFlavor } from 'better-supabase/config';\nimport {\n  toJsonSchema as toSchema,\n  jsonSchema,\n  type Generator,\n} from 'better-supabase/config';\n`;

    expect(moveGeneratorImports(text)).toBe(
      [
        `import type { JsonSchemaTarget } from 'better-supabase/generators/json-schema';`,
        `import type { ZodFlavor } from 'better-supabase/generators/zod';`,
        `import { type Generator } from 'better-supabase/config';`,
        `import { toJsonSchema as toSchema, jsonSchema } from 'better-supabase/generators/json-schema';`,
        "",
      ].join("\n"),
    );
  });

  it("leaves other imports and a config import without generators alone", () => {
    const text = `import { defineConfig } from "better-supabase/config";\nimport { zod } from "zod";\n`;

    expect(moveGeneratorImports(text)).toBe(text);
  });

  it("lists lines that still use the version 1 shape", () => {
    const source = [
      `export const g = {`,
      `  apiVersion: 1,`,
      `  generate: (input) => [{ path: input.importPath("a", "b"), contents: input.runtimeImport, validators: true }],`,
      `};`,
    ].join("\n");

    const { review } = applyCodemod(generatorsCodemod(), source);

    expect(review.map((line) => line.line)).toEqual([2, 3, 3, 3]);
    expect(review.map((line) => line.message).join("\n")).toContain(
      "relativeImport",
    );
  });

  it("does not flag apiVersion 1 in another contract", () => {
    const source = [
      `export const hooks = defineAuthorizationHooks({`,
      `  apiVersion: 1,`,
      `  evict: () => {},`,
      `});`,
      `export const g = {`,
      `  apiVersion: 1,`,
      `  generate: () => [],`,
      `};`,
    ].join("\n");

    const { review } = applyCodemod(generatorsCodemod(), source);

    expect(review.map((line) => line.line)).toEqual([6]);
  });
});
