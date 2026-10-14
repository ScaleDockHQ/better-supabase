import addFormats from "ajv-formats";
import Ajv2020 from "ajv/dist/2020.js";
import { describe, expect, it } from "vitest";

import {
  FORM_DEFINITION_SCHEMA,
  FORM_SCHEMA_DIALECT,
  formSchema,
  validateAnswers,
} from "../../src/blocks/forms/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { SIGNUP } from "../blocks/forms/fixtures.ts";
import { metaSchema2020, problems } from "./validator.ts";

// `then: { required }` names a property declared at the top, which strictRequired doesn't follow.
const ajv = new Ajv2020({
  strict: true,
  strictRequired: false,
  allErrors: true,
});
addFormats(ajv);
const schema = formSchema(SIGNUP);
const answers = ajv.compile(schema);

const BASE = { name: "Ada", email: "ada@example.com" };
const CASES: readonly unknown[] = [
  BASE,
  { ...BASE, plan: "free" },
  { ...BASE, plan: "team", company: "Acme", seats: 5, terms: true },
  { ...BASE, plan: "team" },
  { ...BASE, plan: "team", company: "", seats: 1, terms: false },
  { ...BASE, plan: "gold" },
  { name: "", email: "ada@example.com" },
  { name: "A", email: "not an email" },
  { ...BASE, website: "https://example.com/a?b=1" },
  { ...BASE, website: "example.com" },
  { ...BASE, started: "2026-02-28" },
  { ...BASE, started: "2026-02-30" },
  { ...BASE, started: "2026-13-01" },
  { ...BASE, topics: ["a", "b"] },
  { ...BASE, topics: [] },
  { ...BASE, topics: ["a", "a"] },
  { ...BASE, topics: ["a", "b", "c"] },
  { ...BASE, topics: ["z"] },
  { ...BASE, budget: 10.5 },
  { ...BASE, budget: -1 },
  { ...BASE, seats: 2.5 },
  { ...BASE, notes: "plain" },
  { ...BASE, notes: "<b>" },
  { ...BASE, agree: true, why: "news" },
  { ...BASE, agree: "yes" },
  { ...BASE, meta: { any: ["json", 1, null] } },
  { ...BASE, unknown: 1 },
  { ...BASE, name: "🙂🙂" },
  { ...BASE, name: "x".repeat(501) },
  [],
  "answers",
];

describe("JSON Schema 2020-12 for forms", () => {
  it("pins the dialect the generated schemas declare", () => {
    expect(FORM_SCHEMA_DIALECT).toBe(
      `https://json-schema.org/draft/${SPEC_PINS.jsonSchema}/schema`,
    );
    expect(schema["$schema"]).toBe(FORM_SCHEMA_DIALECT);
    expect(FORM_DEFINITION_SCHEMA["$schema"]).toBe(FORM_SCHEMA_DIALECT);
  });

  it("generates schemas that are valid 2020-12 schemas", () => {
    const meta = metaSchema2020();
    expect(problems(meta, schema)).toEqual([]);
    expect(problems(meta, FORM_DEFINITION_SCHEMA)).toEqual([]);
  });

  it("checks a definition against its own meta-schema", () => {
    const definitions = ajv.compile(FORM_DEFINITION_SCHEMA);
    expect(problems(definitions, SIGNUP)).toEqual([]);
    expect(definitions({ steps: [] })).toBe(false);
    expect(
      definitions({ steps: [{ key: "a", fields: [{ key: "Bad Key" }] }] }),
    ).toBe(false);
  });

  it.each(CASES.map((value) => [JSON.stringify(value).slice(0, 60), value]))(
    "validateAnswers agrees with ajv on %s",
    (_, value) => {
      expect(validateAnswers(schema, value).length === 0).toBe(answers(value));
    },
  );
});
