import type {
  FormDefinition,
  FormField,
  FormJson,
} from "../../core/contracts/form-definition.ts";
import type { FormAnswers } from "./validate.ts";

import { conditionHolds } from "./questionnaire.ts";

/** A scored submission's grade, as `form_score` computes it in Postgres. */
export interface FormScore {
  /** The points the correct answers earned. */
  readonly score: number;
  /** The points of every scored field that showed. */
  readonly maxScore: number;
  /** Against `scoring.passMark`; `undefined` without one. */
  readonly passed?: boolean;
}

/** An `nps` answer's bucket: 9 and 10 promote, 7 and 8 are passive. */
export type NpsCategory = "promoter" | "passive" | "detractor";

const trimmed = (value: string): string =>
  value.replaceAll(/^ +| +$/g, "").toLowerCase();

const TEXT_TYPES: ReadonlySet<string> = new Set([
  "text",
  "textarea",
  "email",
  "url",
]);

/** Whether `answer` earns a field's points. */
function matches(
  field: FormField,
  answer: FormJson,
  correct: FormJson,
): boolean {
  if (TEXT_TYPES.has(field.type ?? "")) {
    return (
      typeof answer === "string" &&
      typeof correct === "string" &&
      trimmed(answer) === trimmed(correct)
    );
  }

  if (field.type === "multi") {
    return (
      Array.isArray(answer) &&
      Array.isArray(correct) &&
      answer.every((value) => correct.includes(value)) &&
      correct.every((value) => answer.includes(value))
    );
  }

  return JSON.stringify(answer) === JSON.stringify(correct);
}

/**
 * The grade of `answers` against a definition with its `correct` answers: the
 * TypeScript twin of `form_score`, for a preview before submitting. A field
 * hidden by its `showIf` (or its step's) counts toward neither score.
 * `undefined` when no field has a correct answer.
 */
export function formScore(
  definition: FormDefinition,
  answers: FormAnswers,
): FormScore | undefined {
  const scored = definition.steps.some((step) =>
    step.fields.some((field) => field.correct !== undefined),
  );

  if (!scored) {
    return undefined;
  }

  let score = 0;
  let maxScore = 0;

  for (const step of definition.steps) {
    if (!conditionHolds(step.showIf, answers)) {
      continue;
    }

    for (const field of step.fields) {
      if (
        field.correct === undefined ||
        !conditionHolds(field.showIf, answers)
      ) {
        continue;
      }

      const points = field.points ?? 1;
      const answer = answers[field.key];
      maxScore += points;

      if (answer !== undefined && matches(field, answer, field.correct)) {
        score += points;
      }
    }
  }

  const passMark = definition.scoring?.passMark;

  return passMark === undefined
    ? { score, maxScore }
    : { score, maxScore, passed: score * 100 >= passMark * maxScore };
}

/** The bucket of an `nps` answer from 0 to 10. */
export function npsCategory(answer: number): NpsCategory {
  if (answer >= 9) {
    return "promoter";
  }

  return answer >= 7 ? "passive" : "detractor";
}

/**
 * The Net Promoter Score of the counts: the promoters' share minus the
 * detractors', from -100 to 100, to one decimal. `undefined` without answers.
 */
export function npsScore(counts: {
  readonly promoters: number;
  readonly passives: number;
  readonly detractors: number;
}): number | undefined {
  const total = counts.promoters + counts.passives + counts.detractors;

  if (total === 0) {
    return undefined;
  }

  const tenths = ((counts.promoters - counts.detractors) * 1000) / total;
  // Halves round away from zero, as Postgres round() does.
  const rounded = Math.round(Math.abs(tenths)) / 10;

  return tenths < 0 && rounded > 0 ? -rounded : rounded;
}
