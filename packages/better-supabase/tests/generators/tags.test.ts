import { describe, expect, it } from "vitest";

import type { GeneratorInput } from "../../src/config/index.ts";

import { tags } from "../../src/generators/tags.ts";

function inputOf(keys: readonly string[]): GeneratorInput {
  // SAFETY: tags() reads only `config.output` and the table keys.
  return {
    config: { output: "/app/src/db.ts" },
    model: { tables: keys.map((key) => ({ key })) },
  } as unknown as GeneratorInput;
}

describe("tags generator", () => {
  it("writes one sorted defineTags call next to the output", async () => {
    const [file] = await tags().generate(inputOf(["tasks", "customers"]));

    expect(file?.path).toBe("/app/src/db.tags.ts");
    expect(file?.contents).toContain(
      'export const tags = defineTags(["customers", "tasks"] as const);',
    );
    expect(file?.contents).toContain(
      'import { defineTags } from "better-supabase/next";',
    );
  });

  it("writes only the tables it names and refuses unknown ones", async () => {
    const [file] = await tags({ tables: ["tasks"] }).generate(
      inputOf(["tasks", "notes"]),
    );

    expect(file?.contents).toContain('defineTags(["tasks"] as const)');
    expect(() =>
      tags({ tables: ["nope"] }).generate(inputOf(["tasks"])),
    ).toThrow('no table named "nope"');
  });
});
