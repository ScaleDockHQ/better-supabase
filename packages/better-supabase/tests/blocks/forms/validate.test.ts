import { describe, expect, it } from "vitest";

import {
  answersSchema,
  formSchema,
  validateAnswers,
} from "../../../src/blocks/forms/index.ts";
import { SIGNUP } from "./fixtures.ts";

const schema = formSchema(SIGNUP);
const BASE = { name: "Ada", email: "ada@example.com" };

const messages = (value: unknown) =>
  validateAnswers(schema, value).map((issue) => [
    issue.path?.join("."),
    issue.message,
  ]);

describe("validateAnswers", () => {
  it("accepts complete answers", () => {
    expect(messages(BASE)).toEqual([]);
    expect(
      messages({
        ...BASE,
        plan: "team",
        company: "Acme",
        seats: 2,
        terms: true,
      }),
    ).toEqual([]);
  });

  it("names the field and the rule that failed", () => {
    expect(messages({})).toEqual([
      ["name", "is required"],
      ["email", "is required"],
    ]);
    expect(messages({ ...BASE, name: "A" })).toEqual([
      ["name", "must be at least 2 characters"],
    ]);
    expect(messages({ ...BASE, name: "x".repeat(501) })).toEqual([
      ["name", "must be at most 500 characters"],
    ]);
    expect(messages({ ...BASE, email: "nope" })).toEqual([
      ["email", "must be a valid email"],
    ]);
    expect(messages({ ...BASE, plan: "gold" })).toEqual([
      ["plan", "must be one of the options"],
    ]);
    expect(messages({ ...BASE, budget: "ten" })).toEqual([
      ["budget", "must be number"],
    ]);
    expect(messages({ ...BASE, budget: Number.NaN })).toEqual([
      ["budget", "must be number"],
    ]);
    expect(messages({ ...BASE, budget: -1 })).toEqual([
      ["budget", "must be at least 0"],
    ]);
    expect(messages({ ...BASE, seats: 501 })).toEqual([
      ["seats", "must be at most 500"],
    ]);
    expect(messages({ ...BASE, terms: false })).toEqual([
      ["terms", "must be true"],
    ]);
    expect(messages({ ...BASE, notes: "<b>" })).toEqual([
      ["notes", "has the wrong format"],
    ]);
    expect(messages({ ...BASE, started: "2026-02-29" })).toEqual([
      ["started", "must be a valid date"],
    ]);
    expect(messages({ ...BASE, website: "not a url" })).toEqual([
      ["website", "must be a valid uri"],
    ]);
    expect(messages({ ...BASE, extra: 1 })).toEqual([
      ["extra", "is not a field of this form"],
    ]);
  });

  it("checks arrays and their items", () => {
    expect(messages({ ...BASE, topics: [] })).toEqual([
      ["topics", "must have at least 1 item"],
    ]);
    expect(messages({ ...BASE, topics: ["a", "b", "c"] })).toEqual([
      ["topics", "must have at most 2 items"],
    ]);
    expect(messages({ ...BASE, topics: ["a", "a"] })).toEqual([
      ["topics", "must not repeat an item"],
    ]);
    expect(messages({ ...BASE, topics: ["z"] })).toEqual([
      ["topics.0", "must be one of the options"],
    ]);
  });

  it("requires a field only when its conditions hold", () => {
    expect(messages({ ...BASE, plan: "team" })).toEqual([
      ["company", "is required"],
      ["seats", "is required"],
      ["terms", "is required"],
    ]);
    expect(messages({ ...BASE, plan: "free" })).toEqual([]);
  });

  it("compares objects and arrays by value", () => {
    const deep = {
      type: "object",
      properties: { a: { const: { x: [1, { y: 2 }] } }, b: { enum: [[1, 2]] } },
    } as const;

    expect(
      validateAnswers(deep, { a: { x: [1, { y: 2 }] }, b: [1, 2] }),
    ).toEqual([]);
    expect(validateAnswers(deep, { a: { x: [1, { y: 3 }] } })).toHaveLength(1);
    expect(validateAnswers(deep, { a: { x: [1] } })).toHaveLength(1);
    expect(validateAnswers(deep, { a: { z: [1, { y: 2 }] } })).toHaveLength(1);
    expect(validateAnswers(deep, { b: [1, 3] })).toHaveLength(1);
    expect(validateAnswers({ type: "null" }, null)).toEqual([]);
    expect(validateAnswers({ type: "mystery" }, 1)).toEqual([]);
    expect(validateAnswers({ type: "string", format: "time" }, "x")).toEqual(
      [],
    );
    expect(validateAnswers({ not: "bad" }, 1)).toHaveLength(1);
  });

  it("rejects answers that are not an object", () => {
    expect(messages([])).toEqual([["", "must be object"]]);
  });
});

describe("answersSchema", () => {
  it("is a Standard Schema over the version's schema", async () => {
    const standard = answersSchema(schema)["~standard"];
    expect(standard.vendor).toBe("better-supabase");
    expect(await standard.validate(BASE)).toEqual({ value: BASE });
    const failed = await standard.validate({});
    expect("issues" in failed && failed.issues).toHaveLength(2);
  });
});
