"use client";

import type {
  QuestionnaireActions,
  QuestionnaireOptions,
  QuestionnaireSnapshot,
} from "better-supabase/blocks/forms";

import { createQuestionnaireController } from "better-supabase/blocks/forms";
import { useController, useLatest } from "better-supabase/react";

export type UseQuestionnaireOptions = QuestionnaireOptions;

export interface QuestionnaireView
  extends QuestionnaireSnapshot, QuestionnaireActions {}

/**
 * A multi-step form over a form version: the visible steps, the answers, and
 * per-field issues checked against the version's JSON Schema. The steps feed a
 * Stepper; the fields render with any input components. A new `form` starts
 * over from `initialAnswers`.
 *
 * ```tsx
 * const q = useQuestionnaire({
 *   form: version,
 *   onSubmit: (answers) => forms.submit(formId, answers),
 * });
 * ```
 */
export function useQuestionnaire(
  options: UseQuestionnaireOptions,
): QuestionnaireView {
  const latest = useLatest(options);
  const { form, initialAnswers } = options;

  return useController(
    () =>
      createQuestionnaireController({
        form,
        ...(initialAnswers === undefined ? {} : { initialAnswers }),
        onSubmit: (answers) => latest.current.onSubmit(answers),
      }),
    [form, latest],
  ).view;
}
