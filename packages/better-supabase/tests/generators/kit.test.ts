import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import * as config from "../../src/config/index.ts";
import { factories } from "../../src/generators/factories/index.ts";
import * as kit from "../../src/generators/index.ts";
import { jsonSchema } from "../../src/generators/json-schema/index.ts";
import { nuqs } from "../../src/generators/nuqs/index.ts";
import { standardSchema } from "../../src/generators/standard-schema/index.ts";
import { valibot } from "../../src/generators/valibot/index.ts";
import { zod } from "../../src/generators/zod/index.ts";
import { testGeneratorPlugin } from "../../src/testing/generator.ts";
import { schema } from "../fixtures/generated-camel.ts";

const generators = join(import.meta.dirname, "../../src/generators");

describe("better-supabase/generators", () => {
  it("builds a generator at the current contract", () => {
    const made = kit.defineGenerator({
      name: "x",
      version: "1.2.3",
      generate: () => [],
    });

    expect(made.apiVersion).toBe(kit.GENERATOR_API_VERSION);
    expect(made.apiVersion).toBe(2);
    expect(config.generatorProblem(made)).toBeUndefined();
  });

  it.each([
    ["src/db/zod.ts", "src/db/generated.ts", "./generated.ts"],
    ["src/db/zod.ts", "src/lib/types.ts", "../lib/types.ts"],
    ["src/zod.ts", "./src/schemas.ts", "./schemas.ts"],
    ["a/b.ts", "c.ts", "../c.ts"],
    ["out.ts", "src/x.ts", "./src/x.ts"],
  ])("relativeImport(%s, %s) is %s", (from, to, expected) => {
    expect(kit.relativeImport(from, to)).toBe(expected);
  });

  it("applies .. segments and ignores empty and . segments", () => {
    expect(kit.relativeImport("a/b/c.ts", "a/../x.ts")).toBe("../../x.ts");
    expect(kit.relativeImport("a//b.ts", "./a/./c.ts")).toBe("./c.ts");
  });

  it("explains a declaration that is not an object", () => {
    expect(config.generatorProblem(null as never)).toContain("is an object");
    expect(
      config.generatorProblem({ apiVersion: 2, version: "1" } as never),
    ).toBeUndefined();
    expect(
      config.generatorProblem({ apiVersion: 3, generate: () => [] } as never),
    ).toContain('generator "(unnamed)" targets generator API 3');
  });

  it("names what a version 1 generator has to change", () => {
    const problem = config.generatorProblem({
      name: "old",
      generate: () => [],
    } as never);

    expect(problem).toContain("targets generator API 1");
    expect(problem).toContain("provides");
    expect(
      config.generatorProblem({
        apiVersion: 2,
        name: "unversioned",
        generate: () => [],
      } as never),
    ).toContain("needs a `version`");
  });

  it.each([
    ["zod", zod()],
    ["valibot", valibot()],
    ["json-schema", jsonSchema()],
    ["standard-schema", standardSchema()],
    ["factories", factories()],
    ["nuqs", nuqs()],
  ])(
    "the %s generator passes testGeneratorPlugin",
    async (_name, generator) => {
      await expect(
        testGeneratorPlugin(generator, { meta: schema.meta }),
      ).resolves.toBeDefined();
      expect(generator.pure).toBe(true);
      expect(generator.workerSafe).toBe(true);
    },
  );

  it("the built-in generators read the contract only through the kit", () => {
    const files = readdirSync(generators).filter(
      (name) => name.endsWith(".ts") && !name.endsWith("kit.ts"),
    );

    const built = [
      "factories",
      "json-schema",
      "nuqs",
      "standard-schema",
      "valibot",
      "zod",
    ];

    for (const name of built) {
      expect(files).toContain(`${name}.ts`);
      const text = readFileSync(join(generators, `${name}.ts`), "utf-8");
      expect(text).not.toMatch(/from "\.\/(shared|extras)\.ts"/);
    }
  });
});
