import { describe, expect, it } from "vitest";

import { toPromptfooConfig } from "../../../src/blocks/ai-evals/promptfoo.ts";
import {
  describeScorer,
  exactMatch,
  jsonSchema,
  llmJudge,
} from "../../../src/blocks/ai-evals/scorers.ts";

const ctx = (output: string, expected: unknown, input: unknown = "q") => ({
  input,
  output,
  expected,
});

describe("exactMatch", () => {
  it("fails without an expected value", async () => {
    const scorer = exactMatch();

    expect((await scorer.score(ctx("a", undefined))).passed).toBe(false);
    expect((await scorer.score(ctx("a", null))).reason).toMatch(/no expected/u);
  });

  it("compares text with and without trimming", async () => {
    expect((await exactMatch().score(ctx(" a ", "a"))).passed).toBe(true);
    expect(
      (await exactMatch({ trim: false, name: "x" }).score(ctx(" a ", "a")))
        .passed,
    ).toBe(false);
    expect((await exactMatch().score(ctx("a", { output: "a" }))).passed).toBe(
      true,
    );
    expect((await exactMatch().score(ctx("b", "a"))).reason).toMatch(
      /differs/u,
    );
  });

  it("compares structured values as canonical json", async () => {
    const scorer = exactMatch();
    const expected = { b: [1, { y: 2, x: 1 }], a: null };

    expect(
      (await scorer.score(ctx('{"a":null,"b":[1,{"x":1,"y":2}]}', expected)))
        .passed,
    ).toBe(true);
    expect((await scorer.score(ctx("not json", expected))).passed).toBe(false);
    expect((await scorer.score(ctx("[1]", { output: 5 }))).passed).toBe(false);
    expect((await scorer.score(ctx("5", 5))).passed).toBe(true);
  });
});

describe("jsonSchema", () => {
  const schema = {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value: unknown) =>
        typeof value === "object" && value !== null
          ? { value }
          : {
              issues: [
                { message: "a" },
                { message: "b" },
                { message: "c" },
                { message: "d" },
              ],
            },
    },
  } as never;

  it("scores json against the schema", async () => {
    const scorer = jsonSchema(schema, { jsonSchema: { type: "object" } });

    expect(scorer.jsonSchema).toEqual({ type: "object" });
    expect((await scorer.score(ctx("{}", undefined))).passed).toBe(true);
    expect((await scorer.score(ctx("nope", undefined))).reason).toMatch(
      /not JSON/u,
    );
    expect((await scorer.score(ctx("5", undefined))).reason).toBe("a; b; c");
    expect(jsonSchema(schema).jsonSchema).toBeUndefined();
  });
});

describe("llmJudge", () => {
  const judgeOf = (
    result: () => Promise<{ score: number; reason?: string }>,
  ) => ({ judge: result });

  it("passes at the threshold and keeps the reason", async () => {
    const scorer = llmJudge(
      judgeOf(() => Promise.resolve({ score: 0.7, reason: "fine" })),
      { criteria: "c" },
    );

    expect(await scorer.score(ctx("o", undefined))).toEqual({
      score: 0.7,
      passed: true,
      reason: "fine",
    });
    expect(
      await llmJudge(
        judgeOf(() => Promise.resolve({ score: 0.1 })),
        { criteria: "c", threshold: 0.5, name: "j" },
      ).score(ctx("o", undefined)),
    ).toEqual({ score: 0.1, passed: false });
  });

  it("fails on a bad score or a throwing judge", async () => {
    for (const score of [Number.NaN, -1, 2]) {
      const result = await llmJudge(
        judgeOf(() => Promise.resolve({ score })),
        { criteria: "c" },
      ).score(ctx("o", undefined));

      expect(result.reason).toMatch(/outside/u);
    }

    expect(
      (
        await llmJudge(
          judgeOf(() => Promise.reject(new Error("down"))),
          { criteria: "c" },
        ).score(ctx("o", undefined))
      ).reason,
    ).toBe("The judge failed: down");
    expect(
      (
        await llmJudge(
          judgeOf(() => Promise.reject("text")),
          { criteria: "c" },
        ).score(ctx("o", undefined))
      ).reason,
    ).toBe("The judge failed: text");
  });
});

describe("describeScorer", () => {
  it("keeps only the stored parts", () => {
    expect(describeScorer(exactMatch())).toEqual({
      name: "exact_match",
      kind: "exact_match",
    });
    expect(
      describeScorer(
        llmJudge(
          { judge: () => Promise.resolve({ score: 1 }) },
          { criteria: "c" },
        ),
      ),
    ).toMatchObject({ criteria: "c", threshold: 0.7 });
    expect(
      describeScorer(
        jsonSchema({} as never, { jsonSchema: { type: "object" } }),
      ).jsonSchema,
    ).toEqual({ type: "object" });
  });
});

describe("toPromptfooConfig", () => {
  const options = (
    scorers: Parameters<typeof toPromptfooConfig>[1]["scorers"],
  ) => ({ description: "d", prompt: "p", model: "m", scorers });

  it("maps vars of every input shape", () => {
    const config = toPromptfooConfig(
      [
        { id: "a", input: { q: "x", n: 1 } },
        { id: "b", input: "text" },
        { id: "c", input: [1] },
        { id: "d", input: null },
      ],
      options([]),
    );

    expect(config.tests.map((test) => test.vars)).toEqual([
      { q: "x", n: "1" },
      { input: "text" },
      { input: "[1]" },
      { input: "null" },
    ]);
  });

  it("maps assertions per scorer and expected value", () => {
    const scorers = [
      describeScorer(exactMatch()),
      describeScorer(
        jsonSchema({} as never, { jsonSchema: { type: "object" } }),
      ),
      describeScorer(jsonSchema({} as never)),
      describeScorer(
        llmJudge(
          { judge: () => Promise.resolve({ score: 1 }) },
          { criteria: "c" },
        ),
      ),
      { name: "j2", kind: "llm_judge" as const },
    ];

    const config = toPromptfooConfig(
      [
        { id: "str", input: "i", expected: "yes" },
        { id: "obj", input: "i", expected: { output: "yes" } },
        { id: "struct", input: "i", expected: { a: 1 } },
        { id: "none", input: "i" },
        { id: "null", input: "i", expected: null },
      ],
      options(scorers),
    );

    const types = (index: number): unknown[] =>
      config.tests[index]?.assert.map((a) => a.type) ?? [];

    expect(types(0)).toContain("equals");
    expect(config.tests[1]?.assert[0]?.value).toBe("yes");
    expect(config.tests[2]?.assert[0]?.value).toBe('{"a":1}');
    expect(types(3)).not.toContain("equals");
    expect(types(4)).not.toContain("equals");
    expect(config.tests[0]?.assert.at(-1)).toEqual({
      type: "llm-rubric",
      value: "",
      metric: "j2",
    });
    expect(
      config.tests[0]?.assert.find((a) => a.type === "llm-rubric"),
    ).toMatchObject({ threshold: 0.7 });
  });
});
