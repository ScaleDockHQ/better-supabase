import type { FormJson } from "../../core/contracts/form-definition.ts";
import type { ValidationIssue } from "../../core/errors.ts";
import type { Controller } from "../controller.ts";
import type {
  QuestionnaireAction,
  QuestionnaireForm,
  QuestionnaireState,
  QuestionnaireStepView,
} from "./questionnaire.ts";
import type { FormAnswers } from "./validate.ts";

import { defineController } from "../controller.ts";
import {
  finishQuestionnaire,
  initialQuestionnaire,
  questionnaireReducer,
  questionnaireSteps,
} from "./questionnaire.ts";

export interface QuestionnaireOptions {
  /** A form version, or anything with its `definition` and `schema`. */
  readonly form: QuestionnaireForm;
  /** Answers to start from, such as a saved draft. */
  readonly initialAnswers?: FormAnswers;
  /** Receives the answers of the visible fields once the whole form passes. */
  readonly onSubmit: (answers: FormAnswers) => Promise<void> | void;
}

export interface QuestionnaireSnapshot {
  /** The visible steps, for a Stepper's items. */
  readonly steps: readonly QuestionnaireStepView[];
  /** The step on screen. */
  readonly step: QuestionnaireStepView | undefined;
  readonly answers: FormAnswers;
  /**
   * Issues by field key: the step on screen's after `next`, every field's after
   * a failed `submit`.
   */
  readonly issues: Readonly<Record<string, readonly string[]>>;
  readonly isFirst: boolean;
  readonly isLast: boolean;
  readonly submitting: boolean;
}

export interface QuestionnaireActions {
  /** `undefined` removes the answer. */
  readonly setAnswer: (key: string, value: FormJson | undefined) => void;
  /** Checks the step and moves to the next visible one. */
  readonly next: () => void;
  readonly back: () => void;
  /** Moves to a step whose earlier steps are done, for a clickable Stepper. */
  readonly goTo: (step: string) => void;
  /** Checks the whole form, then calls `onSubmit`. Returns whether it passed. */
  readonly submit: () => Promise<boolean>;
  readonly reset: (answers?: FormAnswers) => void;
}

export type QuestionnaireController = Controller<
  QuestionnaireSnapshot,
  QuestionnaireActions
>;

function byField(
  issues: readonly ValidationIssue[],
): Readonly<Record<string, readonly string[]>> {
  const out: Record<string, string[]> = {};

  for (const issue of issues) {
    const key = issue.path?.[0];
    const name = typeof key === "string" ? key : "";
    (out[name] ??= []).push(issue.message);
  }

  return out;
}

function viewOf(
  form: QuestionnaireForm,
  current: QuestionnaireState,
  finalIssues: readonly ValidationIssue[],
  submitting: boolean,
): QuestionnaireSnapshot {
  const steps = questionnaireSteps(form, current);
  const index = steps.findIndex((step) => step.active);

  return {
    steps,
    step: steps[index],
    answers: current.answers,
    issues: byField([...current.issues, ...finalIssues]),
    isFirst: index <= 0,
    isLast: index === steps.length - 1,
    submitting,
  };
}

/**
 * A multi-step form over a form version: the visible steps, the answers, and
 * per-field issues checked against the version's JSON Schema.
 */
export function createQuestionnaireController(
  options: QuestionnaireOptions,
): QuestionnaireController {
  const { form } = options;
  let current = initialQuestionnaire(form, options.initialAnswers);
  let finalIssues: readonly ValidationIssue[] = [];
  let submitting = false;

  return defineController<QuestionnaireSnapshot, QuestionnaireActions>(
    viewOf(form, current, finalIssues, submitting),
    (state) => {
      const show = (): void => {
        state.set(viewOf(form, current, finalIssues, submitting));
      };

      const dispatch = (action: QuestionnaireAction): void => {
        current = questionnaireReducer(form, current, action);
        show();
      };

      return {
        actions: {
          setAnswer: (key, value) => {
            finalIssues = finalIssues.filter(
              (issue) => issue.path?.[0] !== key,
            );
            dispatch({ type: "answer", key, value });
          },
          next: () => {
            dispatch({ type: "next" });
          },
          back: () => {
            dispatch({ type: "back" });
          },
          goTo: (step) => {
            dispatch({ type: "goTo", step });
          },
          reset: (answers) => {
            finalIssues = [];
            dispatch(
              answers === undefined
                ? { type: "reset" }
                : { type: "reset", answers },
            );
          },
          submit: async () => {
            const result = finishQuestionnaire(form, current);

            if (!result.ok) {
              finalIssues = result.issues;
              show();

              return false;
            }

            submitting = true;
            show();

            try {
              await options.onSubmit(result.answers);
            } finally {
              submitting = false;
              show();
            }

            return true;
          },
        },
      };
    },
  );
}
