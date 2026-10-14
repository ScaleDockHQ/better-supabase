"use client";

import { useCallback, useMemo, useReducer, useState } from "react";

import type { FormJson } from "../../../core/contracts/form-definition.ts";
import type { ValidationIssue } from "../../../core/errors.ts";
import type {
  QuestionnaireAction,
  QuestionnaireForm,
  QuestionnaireState,
  QuestionnaireStepView,
} from "../questionnaire.ts";
import type { FormAnswers } from "../validate.ts";

import {
  finishQuestionnaire,
  initialQuestionnaire,
  questionnaireReducer,
  questionnaireSteps,
} from "../questionnaire.ts";

export interface UseQuestionnaireOptions {
  /** A form version, or anything with its `definition` and `schema`. */
  readonly form: QuestionnaireForm;
  /** Answers to start from, such as a saved draft. */
  readonly initialAnswers?: FormAnswers;
  /** Receives the answers of the visible fields once the whole form passes. */
  readonly onSubmit: (answers: FormAnswers) => Promise<void> | void;
}

export interface QuestionnaireView {
  /** The visible steps, for a Stepper's items. */
  readonly steps: readonly QuestionnaireStepView[];
  /** The step on screen. */
  readonly step: QuestionnaireStepView | undefined;
  readonly answers: FormAnswers;
  /** Issues by field key: the step on screen's after `next`, every field's after a failed `submit`. */
  readonly issues: Readonly<Record<string, readonly string[]>>;
  readonly isFirst: boolean;
  readonly isLast: boolean;
  readonly submitting: boolean;
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

/**
 * A multi-step form over a form version: the visible steps, the answers,
 * and per-field issues checked against the version's JSON Schema. The
 * steps feed a Stepper; the fields render with any input components.
 *
 * ```tsx
 * const q = useQuestionnaire({ form: version, onSubmit: (answers) => forms.submit(formId, answers) });
 * ```
 */
export function useQuestionnaire(
  options: UseQuestionnaireOptions,
): QuestionnaireView {
  const { form, initialAnswers, onSubmit } = options;
  const [state, dispatch] = useReducer(
    (current: QuestionnaireState, action: QuestionnaireAction) =>
      questionnaireReducer(form, current, action),
    initialAnswers,
    (answers) => initialQuestionnaire(form, answers),
  );
  const [submitting, setSubmitting] = useState(false);
  const [finalIssues, setFinalIssues] = useState<readonly ValidationIssue[]>(
    [],
  );
  const steps = useMemo(() => questionnaireSteps(form, state), [form, state]);
  const index = steps.findIndex((step) => step.active);

  const setAnswer = useCallback((key: string, value: FormJson | undefined) => {
    setFinalIssues((issues) =>
      issues.filter((issue) => issue.path?.[0] !== key),
    );
    dispatch({ type: "answer", key, value });
  }, []);
  const next = useCallback(() => {
    dispatch({ type: "next" });
  }, []);
  const back = useCallback(() => {
    dispatch({ type: "back" });
  }, []);
  const goTo = useCallback((step: string) => {
    dispatch({ type: "goTo", step });
  }, []);
  const reset = useCallback((answers?: FormAnswers) => {
    setFinalIssues([]);
    dispatch(
      answers === undefined ? { type: "reset" } : { type: "reset", answers },
    );
  }, []);
  const submit = useCallback(async () => {
    const result = finishQuestionnaire(form, state);
    if (!result.ok) {
      setFinalIssues(result.issues);
      return false;
    }
    setSubmitting(true);
    try {
      await onSubmit(result.answers);
    } catch (error) {
      setSubmitting(false);
      throw error;
    }
    setSubmitting(false);
    return true;
  }, [form, state, onSubmit]);

  return {
    steps,
    step: steps[index],
    answers: state.answers,
    issues: byField([...state.issues, ...finalIssues]),
    isFirst: index <= 0,
    isLast: index === steps.length - 1,
    submitting,
    setAnswer,
    next,
    back,
    goTo,
    submit,
    reset,
  };
}
