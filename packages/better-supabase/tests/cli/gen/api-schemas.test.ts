import { describe, expect, it } from "vitest";

import { apiTypeSchemas } from "../../../src/cli/gen/api-schemas.ts";

type Input = Parameters<typeof apiTypeSchemas>[0];

const input = (overrides: Partial<Input>): Input => ({
  blocks: {},
  gen: {},
  schemas: ["public"],
  ...overrides,
});

describe("apiTypeSchemas", () => {
  it("lists the block API schemas that config.schemas leaves out, sorted", () => {
    expect(
      apiTypeSchemas(
        input({
          blocks: {
            comments: { api: "zeta" },
            tasks: { api: "api" },
            deals: { api: "api" },
            billing: { api: "public" },
            audit: {},
            support: { api: false },
          },
        }),
      ),
    ).toStrictEqual(["api", "zeta"]);
  });

  it("returns none when gen.api.types is false", () => {
    expect(
      apiTypeSchemas(
        input({
          blocks: { tasks: { api: "api" } },
          gen: { api: { types: false } },
        }),
      ),
    ).toStrictEqual([]);
  });

  it("returns none without blocks", () => {
    expect(apiTypeSchemas(input({}))).toStrictEqual([]);
  });
});
