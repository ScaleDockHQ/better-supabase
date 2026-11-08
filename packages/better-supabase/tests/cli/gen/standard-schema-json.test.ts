import { describe, expect, it } from "vitest";

import { renderFiles } from "../../../src/cli/gen/render.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { standardSchema } from "../../../src/generators/standard-schema.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

const mainOf = async (
  gen: NonNullable<Parameters<typeof resolveConfig>[0]["gen"]>,
): Promise<string | undefined> => {
  const config = resolveConfig(
    { gen: { file: "src/db/generated.ts", ...gen } },
    "/project",
  );

  return (
    await renderFiles(config, await loadFixtureSnapshot(), {
      extensions: false,
    })
  ).find((file) => file.path === "src/db/generated.ts")?.contents;
};

describe("gen.json from the Standard Schema setup", () => {
  it("types a column from its schema value", async () => {
    const main = await mainOf({
      generators: [
        standardSchema({
          json: { "customers.metadata": "./src/schemas.ts#metadata" },
        }),
      ],
    });

    expect(main).toContain("StandardSchemaV1.InferOutput<typeof metadata>");
    expect(main).toContain('import type { metadata } from "../schemas.ts";');
    expect(main).toContain(
      'import type { StandardSchemaV1 } from "better-supabase";',
    );
  });

  it("lets gen.json win and adds no import without a schema", async () => {
    const main = await mainOf({
      json: { "customers.metadata": { type: "Kept" } },
      generators: [
        standardSchema({
          json: { "customers.metadata": "./src/schemas.ts#metadata" },
        }),
      ],
    });

    expect(main).toContain("Kept");
    expect(main).not.toContain("typeof metadata");
    expect(await mainOf({})).not.toContain("StandardSchemaV1");
  });

  it("rejects a schema reference without a name", async () => {
    await expect(
      mainOf({
        generators: [
          standardSchema({ json: { "customers.metadata": "./schemas.ts" } }),
        ],
      }),
    ).rejects.toThrow(/schemaName/);
  });
});
