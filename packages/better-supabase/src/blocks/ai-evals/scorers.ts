import type { StandardSchemaV1 } from "@standard-schema/spec";

import { injectableOf } from "../shared.ts";

/** What a scorer returns for one item. */
export interface ScoreResult {
  /** 0 to 1. */
  readonly score: number;
  readonly passed: boolean;
  readonly reason?: string;
}

/** What a scorer reads for one item. */
export interface ScoreInput {
  readonly input: unknown;
  /** The model's answer. */
  readonly output: string;
  /** The item's `expected` value, when it has one. */
  readonly expected: unknown;
}

/** The kinds a run stores and `toPromptfooConfig` maps. */
export type ScorerKind = "exact_match" | "json_schema" | "llm_judge";

/** What a run keeps about a scorer, and what the promptfoo export reads. */
export interface ScorerDescription {
  readonly name: string;
  readonly kind: ScorerKind;
  /** `llm_judge`: the rubric the judge grades against. */
  readonly criteria?: string;
  /** `llm_judge`: the lowest score that passes. */
  readonly threshold?: number;
  /**
   * `json_schema`: a plain JSON Schema for the export; scoring uses the schema
   * object.
   */
  readonly jsonSchema?: Readonly<Record<string, unknown>>;
}

export interface EvalScorer extends ScorerDescription {
  score(input: ScoreInput): Promise<ScoreResult>;
}

/**
 * An LLM judge you supply: it calls the model of your choice and returns a
 * score. Nothing here depends on a model SDK.
 */
export interface EvalJudge {
  /** The contract version; omit for 1. */
  readonly apiVersion?: 1;
  judge(input: {
    readonly criteria: string;
    readonly input: unknown;
    readonly output: string;
    readonly expected: unknown;
  }): Promise<{ readonly score: number; readonly reason?: string }>;
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonical).join(",")}]`;
  }

  if (value !== null && typeof value === "object") {
    return `{${Object.entries(value)
      .toSorted(([a], [b]) => (a < b ? -1 : 1))
      .map(([key, entry]) => `${JSON.stringify(key)}:${canonical(entry)}`)
      .join(",")}}`;
  }

  return JSON.stringify(value);
}

function parseJson(text: string): { readonly value: unknown } | undefined {
  try {
    return { value: JSON.parse(text) };
  } catch {
    return;
  }
}

function expectedText(expected: unknown): string | undefined {
  if (typeof expected === "string") {
    return expected;
  }

  if (
    expected !== null &&
    typeof expected === "object" &&
    "output" in expected &&
    typeof expected.output === "string"
  ) {
    return expected.output;
  }

  return;
}

/**
 * Passes when the output equals the item's `expected` value. A string (or an
 * object with an `output` string) compares as text; any other value compares to
 * the output parsed as JSON, with object keys in any order.
 */
export function exactMatch(
  options: { readonly name?: string; readonly trim?: boolean } = {},
): EvalScorer {
  const trim = options.trim ?? true;
  const prepare = (text: string): string => (trim ? text.trim() : text);

  return {
    name: options.name ?? "exact_match",
    kind: "exact_match",
    score: ({ output, expected }) => {
      if (expected === undefined || expected === null) {
        return Promise.resolve({
          score: 0,
          passed: false,
          reason: "The item has no expected value",
        });
      }

      const text = expectedText(expected);

      const matches =
        text === undefined
          ? (() => {
              const parsed = parseJson(output);

              return (
                parsed !== undefined &&
                canonical(parsed.value) === canonical(expected)
              );
            })()
          : prepare(output) === prepare(text);

      return Promise.resolve({
        score: matches ? 1 : 0,
        passed: matches,
        ...(matches
          ? {}
          : { reason: "The output differs from the expected value" }),
      });
    },
  };
}

/**
 * Passes when the output is JSON that a Standard Schema accepts (Zod, Valibot,
 * ArkType and others). Pass `jsonSchema` too when you export to promptfoo.
 */
export function jsonSchema(
  schema: StandardSchemaV1,
  options: {
    readonly name?: string;
    readonly jsonSchema?: Readonly<Record<string, unknown>>;
  } = {},
): EvalScorer {
  return {
    name: options.name ?? "json_schema",
    kind: "json_schema",
    ...(options.jsonSchema ? { jsonSchema: options.jsonSchema } : {}),
    score: async ({ output }) => {
      const parsed = parseJson(output);

      if (parsed === undefined) {
        return { score: 0, passed: false, reason: "The output is not JSON" };
      }

      const result = await schema["~standard"].validate(parsed.value);

      if (result.issues === undefined) {
        return { score: 1, passed: true };
      }

      return {
        score: 0,
        passed: false,
        reason: result.issues
          .slice(0, 3)
          .map((issue) => issue.message)
          .join("; "),
      };
    },
  };
}

/**
 * Asks your judge to grade the output against `criteria`; the score passes at
 * `threshold` (default 0.7). A judge that throws or returns a score outside 0
 * to 1 fails the item with the reason, so one bad call does not end a run.
 */
export function llmJudge(
  judge: EvalJudge,
  options: {
    readonly criteria: string;
    readonly name?: string;
    readonly threshold?: number;
  },
): EvalScorer {
  const port = injectableOf("ai-evals judge", judge);
  const threshold = options.threshold ?? 0.7;

  return {
    name: options.name ?? "llm_judge",
    kind: "llm_judge",
    criteria: options.criteria,
    threshold,
    score: async ({ input, output, expected }) => {
      try {
        const graded = await port.judge({
          criteria: options.criteria,
          input,
          output,
          expected,
        });

        if (
          !Number.isFinite(graded.score) ||
          graded.score < 0 ||
          graded.score > 1
        ) {
          return {
            score: 0,
            passed: false,
            reason: "The judge returned a score outside 0 to 1",
          };
        }

        return {
          score: graded.score,
          passed: graded.score >= threshold,
          ...(graded.reason === undefined ? {} : { reason: graded.reason }),
        };
      } catch (error) {
        return {
          score: 0,
          passed: false,
          reason: `The judge failed: ${error instanceof Error ? error.message : String(error)}`,
        };
      }
    },
  };
}

/** The part of a scorer a run stores. */
export function describeScorer(scorer: EvalScorer): ScorerDescription {
  return {
    name: scorer.name,
    kind: scorer.kind,
    ...(scorer.criteria === undefined ? {} : { criteria: scorer.criteria }),
    ...(scorer.threshold === undefined ? {} : { threshold: scorer.threshold }),
    ...(scorer.jsonSchema === undefined
      ? {}
      : { jsonSchema: scorer.jsonSchema }),
  };
}
