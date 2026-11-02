import type { ScorerDescription } from "./scorers.ts";

/** One promptfoo assertion. */
export interface PromptfooAssertion {
  readonly type: string;
  readonly value?: unknown;
  readonly threshold?: number;
  readonly metric?: string;
}

export interface PromptfooTest {
  readonly description?: string;
  readonly vars: Readonly<Record<string, string>>;
  readonly assert: readonly PromptfooAssertion[];
}

/** A promptfoo config as a plain object; write it with `JSON.stringify`. */
export interface PromptfooConfig {
  readonly description: string;
  readonly prompts: readonly string[];
  readonly providers: readonly string[];
  readonly tests: readonly PromptfooTest[];
}

export interface PromptfooItem {
  readonly id: string;
  readonly input: unknown;
  readonly expected?: unknown;
}

export interface PromptfooOptions {
  readonly description: string;
  /**
   * The prompt template, with `{{name}}` placeholders (the `prompts` block's
   * format).
   */
  readonly prompt: string;
  /** The promptfoo provider id, such as `openai:gpt-4.1-mini`. */
  readonly model: string;
  readonly scorers: readonly ScorerDescription[];
}

function varsOf(input: unknown): Record<string, string> {
  if (input !== null && typeof input === "object" && !Array.isArray(input)) {
    return Object.fromEntries(
      Object.entries(input).map(([key, value]) => [
        key,
        typeof value === "string" ? value : JSON.stringify(value),
      ]),
    );
  }

  return { input: typeof input === "string" ? input : JSON.stringify(input) };
}

function expectedOf(expected: unknown): unknown {
  return expected !== null &&
    typeof expected === "object" &&
    "output" in expected &&
    typeof expected.output === "string"
    ? expected.output
    : expected;
}

function assertionsOf(
  scorer: ScorerDescription,
  expected: unknown,
): PromptfooAssertion[] {
  switch (scorer.kind) {
    case "exact_match": {
      const value = expectedOf(expected);

      if (value === undefined || value === null) {
        return [];
      }

      return typeof value === "string"
        ? [{ type: "equals", value, metric: scorer.name }]
        : [
            {
              type: "equals",
              value: JSON.stringify(value),
              metric: scorer.name,
            },
          ];
    }

    case "json_schema": {
      return [
        {
          type: "is-json",
          ...(scorer.jsonSchema ? { value: scorer.jsonSchema } : {}),
          metric: scorer.name,
        },
      ];
    }

    case "llm_judge": {
      return [
        {
          type: "llm-rubric",
          value: scorer.criteria ?? "",
          ...(scorer.threshold === undefined
            ? {}
            : { threshold: scorer.threshold }),
          metric: scorer.name,
        },
      ];
    }

    default: {
      const unreachable: never = scorer.kind;

      return unreachable;
    }
  }
}

/**
 * A promptfoo config for a dataset: one test per item, the item's input as
 * variables and one assertion per scorer. Exact match needs an expected value
 * on the item and is left out of an item without one.
 */
export function toPromptfooConfig(
  items: readonly PromptfooItem[],
  options: PromptfooOptions,
): PromptfooConfig {
  return {
    description: options.description,
    prompts: [options.prompt],
    providers: [options.model],
    tests: items.map((item) => ({
      description: item.id,
      vars: varsOf(item.input),
      assert: options.scorers.flatMap((scorer) =>
        assertionsOf(scorer, item.expected),
      ),
    })),
  };
}
