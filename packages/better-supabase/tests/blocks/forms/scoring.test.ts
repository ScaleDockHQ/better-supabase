import { describe, expect, it } from "vitest";

import type { FormDefinition } from "../../../src/blocks/forms/index.ts";

import {
  formDefinitionProblems,
  formScore,
  npsCategory,
  npsScore,
} from "../../../src/blocks/forms/index.ts";

const QUIZ: FormDefinition = {
  scoring: { passMark: 60 },
  steps: [
    {
      key: "quiz",
      fields: [
        { key: "capital", type: "text", label: "Capital", correct: "Paris" },
        {
          key: "planets",
          type: "multi",
          label: "Gas giants",
          options: [
            { value: "jupiter", label: "Jupiter" },
            { value: "saturn", label: "Saturn" },
            { value: "mars", label: "Mars" },
          ],
          correct: ["jupiter", "saturn"],
          points: 2,
        },
        { key: "year", type: "number", label: "Year", correct: 1969 },
        { key: "nps", type: "nps", label: "Recommend us?" },
      ],
    },
    {
      key: "bonus",
      showIf: { field: "capital", equals: "Paris" },
      fields: [{ key: "bonus", type: "bool", label: "Bonus", correct: true }],
    },
  ],
};

describe("formScore", () => {
  it("is a valid definition", () => {
    expect(formDefinitionProblems(QUIZ)).toEqual([]);
  });

  it("grades text without case and spaces, multi as a set, the rest as JSON", () => {
    expect(
      formScore(QUIZ, {
        capital: "  paris ",
        planets: ["saturn", "jupiter"],
        year: 1969,
        nps: 10,
      }),
    ).toEqual({ score: 4, maxScore: 4, passed: true });
  });

  it("counts a field its step hides toward neither score", () => {
    expect(
      formScore(QUIZ, { capital: "Lyon", planets: ["jupiter"], year: 1969 }),
    ).toEqual({ score: 1, maxScore: 4, passed: false });
    expect(
      formScore(QUIZ, {
        capital: "Paris",
        planets: ["jupiter", "saturn"],
        bonus: true,
      }),
    ).toEqual({ score: 4, maxScore: 5, passed: true });
  });

  it("passes at the mark exactly and leaves passed out without one", () => {
    expect(
      formScore(QUIZ, { capital: "Lyon", planets: ["jupiter", "saturn"] }),
    ).toEqual({ score: 2, maxScore: 4, passed: false });
    expect(
      formScore(
        { ...QUIZ, scoring: { passMark: 50 } },
        { capital: "Lyon", planets: ["jupiter", "saturn"] },
      ),
    ).toEqual({ score: 2, maxScore: 4, passed: true });
    const { scoring: _, ...unmarked } = QUIZ;
    expect(formScore(unmarked, {})).toEqual({ score: 0, maxScore: 4 });
  });

  it("refuses an answer of the wrong JSON type", () => {
    expect(
      formScore(QUIZ, { capital: 1, planets: "jupiter", year: "1969" }),
    ).toEqual({ score: 0, maxScore: 4, passed: false });
  });

  it("is undefined for a form without correct answers", () => {
    expect(
      formScore(
        {
          steps: [
            { key: "nps", fields: [{ key: "nps", type: "nps", label: "NPS" }] },
          ],
        },
        { nps: 9 },
      ),
    ).toBeUndefined();
  });
});

describe("nps", () => {
  it("buckets answers", () => {
    expect([0, 6, 7, 8, 9, 10].map(npsCategory)).toEqual([
      "detractor",
      "detractor",
      "passive",
      "passive",
      "promoter",
      "promoter",
    ]);
  });

  it("scores to one decimal and rounds halves away from zero", () => {
    expect(
      npsScore({ promoters: 0, passives: 0, detractors: 0 }),
    ).toBeUndefined();
    expect(npsScore({ promoters: 2, passives: 1, detractors: 1 })).toBe(25);
    expect(npsScore({ promoters: 1, passives: 1, detractors: 1 })).toBe(0);
    expect(npsScore({ promoters: 2, passives: 0, detractors: 1 })).toBe(33.3);
    expect(npsScore({ promoters: 1, passives: 0, detractors: 2 })).toBe(-33.3);
    expect(npsScore({ promoters: 0, passives: 1999, detractors: 1 })).toBe(
      -0.1,
    );
    expect(npsScore({ promoters: 0, passives: 3999, detractors: 1 })).toBe(0);
    expect(
      Object.is(npsScore({ promoters: 0, passives: 3999, detractors: 1 }), -0),
    ).toBe(false);
    expect(npsScore({ promoters: 0, passives: 0, detractors: 4 })).toBe(-100);
  });
});
