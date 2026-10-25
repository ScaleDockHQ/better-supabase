import { describe, expect, it } from "vitest";

import {
  blockOptions,
  option,
  optionsJsonSchema,
} from "../../src/blocks/options.ts";

type Options = {
  readonly extraColumns?: Readonly<Record<string, string>>;
  readonly idType?: "uuid" | "bigint";
};

const schema = blockOptions<Options>({
  extraColumns: option.extraColumns(),
  idType: option.string<"uuid" | "bigint">({ default: "uuid" }),
});

const validate = (value: unknown) => schema["~standard"].validate(value);

describe("option.extraColumns", () => {
  it("takes column names mapped to SQL types", () => {
    expect(
      validate({ extraColumns: { region: "text", tags: "text[]" } }),
    ).toEqual({ value: { extraColumns: { region: "text", tags: "text[]" } } });
    expect(validate({ extraColumns: {} })).toEqual({
      value: { extraColumns: {} },
    });
  });

  it("refuses a list or a type that is not a string", () => {
    for (const extraColumns of [["region"], { region: 1 }, "region text"]) {
      expect(validate({ extraColumns })).toEqual({
        issues: [
          {
            message:
              '"extraColumns" must be an object of column names to SQL types',
            path: ["extraColumns"],
          },
        ],
      });
    }
  });

  it("writes an object of strings into the JSON Schema", () => {
    expect(optionsJsonSchema(schema)).toMatchObject({
      properties: {
        extraColumns: {
          type: "object",
          additionalProperties: { type: "string" },
        },
        idType: { type: "string", default: "uuid" },
      },
    });
  });
});
