import { describe, expect, it } from "vitest";

import {
  conditionSchema,
  FORM_FIELD_TYPES,
  FORM_SCHEMA_DIALECT,
  fieldSchema,
  formDefinitionProblems,
  formSchema,
  isFormDefinition,
} from "../../../src/core/contracts/form-definition.ts";
import { SIGNUP } from "../../blocks/forms/fixtures.ts";

const requiredWhen = (condition: unknown, key: string) => ({
  if: condition,
  // oxlint-disable-next-line unicorn/no-thenable -- the JSON Schema keyword
  then: { required: [key] },
});

describe("fieldSchema", () => {
  it("maps every field type", () => {
    const options = [{ value: "a", label: "A" }];

    const schemas = Object.fromEntries(
      FORM_FIELD_TYPES.map((type) => [
        type,
        fieldSchema({ key: "k", label: "K", type, options }),
      ]),
    );

    expect(schemas).toEqual({
      text: { type: "string", maxLength: 500, title: "K" },
      textarea: { type: "string", maxLength: 10_000, title: "K" },
      email: { type: "string", format: "email", maxLength: 320, title: "K" },
      url: { type: "string", format: "uri", maxLength: 2000, title: "K" },
      number: { type: "number", title: "K" },
      integer: { type: "integer", title: "K" },
      date: { type: "string", format: "date", title: "K" },
      bool: { type: "boolean", title: "K" },
      consent: { type: "boolean", const: true, title: "K" },
      option: { type: "string", enum: ["a"], title: "K" },
      multi: {
        type: "array",
        items: { type: "string", enum: ["a"] },
        uniqueItems: true,
        title: "K",
      },
      json: { title: "K" },
    });
  });

  it("gives a required field a floor so an empty answer fails", () => {
    expect(
      fieldSchema({ key: "k", type: "text", required: true }),
    ).toMatchObject({
      minLength: 1,
    });
    expect(
      fieldSchema({
        key: "k",
        type: "text",
        required: true,
        minLength: 3,
        maxLength: 9,
      }),
    ).toMatchObject({ minLength: 3, maxLength: 9 });
    expect(
      fieldSchema({ key: "k", type: "multi", required: true, options: [] }),
    ).toMatchObject({ minItems: 1 });
  });

  it("keeps help as the description", () => {
    expect(
      fieldSchema({ key: "k", type: "bool", label: "K", help: "Why" }),
    ).toEqual({
      type: "boolean",
      title: "K",
      description: "Why",
    });
  });

  it("throws for a customField that publishing has not resolved", () => {
    expect(() => fieldSchema({ key: "k", customField: "d1" })).toThrow(
      /customField/,
    );
  });
});

describe("formSchema", () => {
  it("declares the 2020-12 dialect and closes the object", () => {
    const schema = formSchema(SIGNUP);
    expect(schema).toMatchObject({
      $schema: FORM_SCHEMA_DIALECT,
      type: "object",
      additionalProperties: false,
      required: ["name", "email"],
    });
  });

  it("requires conditional fields through if and then", () => {
    expect(formSchema(SIGNUP)["allOf"]).toEqual([
      requiredWhen(
        conditionSchema({ field: "plan", equals: "team" }),
        "company",
      ),
      requiredWhen(conditionSchema({ field: "plan", in: ["team"] }), "seats"),
      requiredWhen(conditionSchema({ field: "plan", in: ["team"] }), "terms"),
    ]);

    const both = formSchema({
      steps: [
        { key: "a", fields: [{ key: "x", label: "X", type: "bool" }] },
        {
          key: "b",
          showIf: { field: "x", equals: true },
          fields: [
            {
              key: "y",
              label: "Y",
              type: "text",
              required: true,
              showIf: { field: "x", filled: true },
            },
          ],
        },
      ],
    });

    expect(both["allOf"]).toEqual([
      requiredWhen(
        {
          allOf: [
            conditionSchema({ field: "x", equals: true }),
            conditionSchema({ field: "x", filled: true }),
          ],
        },
        "y",
      ),
    ]);
    expect(both).not.toHaveProperty("required");
  });

  it("writes a filled condition as not empty", () => {
    expect(conditionSchema({ field: "x", filled: true })).toEqual({
      properties: { x: { not: { enum: [null, "", []] } } },
      required: ["x"],
    });
  });
});

describe("definition checks", () => {
  it("recognizes the outline of a definition", () => {
    expect(isFormDefinition(SIGNUP)).toBe(true);

    for (const bad of [
      null,
      [],
      {},
      { steps: [1] },
      { steps: [{ key: 1, fields: [] }] },
    ]) {
      expect(isFormDefinition(bad)).toBe(false);
    }

    expect(
      isFormDefinition({ steps: [{ key: "a", fields: [{ label: "x" }] }] }),
    ).toBe(false);
  });

  it("finds what the shape can't say", () => {
    expect(formDefinitionProblems(SIGNUP)).toEqual([]);
    expect(
      formDefinitionProblems({
        steps: [
          {
            key: "a",
            showIf: { field: "later", filled: true },
            fields: [{ key: "x" }],
          },
          {
            key: "a",
            fields: [
              {
                key: "x",
                label: "X",
                type: "text",
                showIf: { field: "nope", equals: 1 },
              },
              { key: "o", label: "O", type: "option" },
              { key: "c", customField: "d1" },
              { key: "m", customField: "d2", type: "multi" },
            ],
          },
        ],
      }),
    ).toEqual([
      "step a: showIf names later, which isn't an earlier field",
      "field x needs a label and a type, or a customField",
      "step a is listed twice",
      "field x is listed twice",
      "field x: showIf names nope, which isn't an earlier field",
      "field o needs options",
    ]);
  });
});
