import { describe, expect, it } from "vitest";

import {
  blockOptions,
  option,
  optionsJsonSchema,
} from "../../src/blocks/options.ts";

type Options = {
  readonly patch?: boolean;
  readonly idType?: "uuid" | "bigint";
};

const schema = blockOptions<Options>({
  patch: option.boolean(),
  idType: option.string<"uuid" | "bigint">({ default: "uuid" }),
});

const validate = (value: unknown) => schema["~standard"].validate(value);

describe("removed options", () => {
  it("names the codemod for an extraColumns option", () => {
    for (const key of ["extraColumns", "lineExtraColumns"]) {
      expect(validate({ [key]: { region: "text" } })).toEqual({
        issues: [
          {
            message: `Option "${key}" was removed: write the column in your schema files. Run "better-supabase codemod extra-columns" to move it`,
            path: [key],
          },
        ],
      });
    }
  });

  it("calls any other key unknown", () => {
    expect(validate({ region: 1 })).toEqual({
      issues: [{ message: 'Unknown option "region"', path: ["region"] }],
    });
  });

  it("writes the option kinds into the JSON Schema", () => {
    expect(optionsJsonSchema(schema)).toMatchObject({
      properties: {
        patch: { type: "boolean" },
        idType: { type: "string", default: "uuid" },
      },
    });
  });
});

describe("blockOptions", () => {
  it("refuses options that are not an object", async () => {
    expect(await schema["~standard"].validate("all")).toEqual({
      issues: [{ message: "Expected an object" }],
    });
  });
});
