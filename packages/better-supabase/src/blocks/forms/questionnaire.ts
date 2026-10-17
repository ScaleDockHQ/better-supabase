import type {
  FormCondition,
  FormDefinition,
  FormField,
  FormJson,
  FormJsonSchema,
  FormStep,
} from "../../core/contracts/form-definition.ts";
import type { ValidationIssue } from "../../core/errors.ts";
import type { FormAnswers } from "./validate.ts";

import { validateAnswers } from "./validate.ts";

function same(a: FormJson | undefined, b: FormJson): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

const EMPTY: ReadonlySet<FormJson> = new Set<FormJson>([null, ""]);

/** Whether `condition` holds for `answers`, with the semantics of its JSON Schema `if`. */
export function conditionHolds(
  condition: FormCondition | undefined,
  answers: FormAnswers,
): boolean {
  if (condition === undefined) {
    return true;
  }

  if (!(condition.field in answers)) {
    return false;
  }

  const value = answers[condition.field];

  if ("equals" in condition) {
    return same(value, condition.equals);
  }

  if ("in" in condition) {
    return condition.in.some((item) => same(value, item));
  }

  return !(
    value === undefined ||
    EMPTY.has(value) ||
    (Array.isArray(value) && value.length === 0)
  );
}

/** The steps whose `showIf` holds. */
export function visibleSteps(
  definition: FormDefinition,
  answers: FormAnswers,
): readonly FormStep[] {
  return definition.steps.filter((step) =>
    conditionHolds(step.showIf, answers),
  );
}

/** The step's fields whose `showIf` holds. */
export function visibleFields(
  step: FormStep,
  answers: FormAnswers,
): readonly FormField[] {
  return step.fields.filter((field) => conditionHolds(field.showIf, answers));
}

function visibleKeys(
  definition: FormDefinition,
  answers: FormAnswers,
): ReadonlySet<string> {
  return new Set(
    visibleSteps(definition, answers).flatMap((step) =>
      visibleFields(step, answers).map((field) => field.key),
    ),
  );
}

/**
 * The answers without the ones for hidden steps and fields. Removing an
 * answer can hide a later field, so it repeats until nothing changes.
 */
export function pruneAnswers(
  definition: FormDefinition,
  answers: FormAnswers,
): FormAnswers {
  const keep = visibleKeys(definition, answers);

  const next = Object.fromEntries(
    Object.entries(answers).filter(([key]) => keep.has(key)),
  );

  return Object.keys(next).length === Object.keys(answers).length
    ? next
    : pruneAnswers(definition, next);
}

/** The schema's issues for the fields `step` shows. */
export function stepIssues(
  schema: FormJsonSchema,
  step: FormStep,
  answers: FormAnswers,
): readonly ValidationIssue[] {
  const keys = new Set(visibleFields(step, answers).map((field) => field.key));

  return validateAnswers(schema, answers).filter((issue) => {
    const key = issue.path?.[0];

    return typeof key === "string" && keys.has(key);
  });
}

export interface QuestionnaireState {
  /** The step on screen, by key. */
  readonly step: string;
  readonly answers: FormAnswers;
  /** The steps that passed their checks on `next`. */
  readonly completed: readonly string[];
  /** The issues of the step on screen after a `next` or `submit` that failed. */
  readonly issues: readonly ValidationIssue[];
}

export type QuestionnaireAction =
  | {
      readonly type: "answer";
      readonly key: string;
      readonly value: FormJson | undefined;
    }
  | { readonly type: "next" }
  | { readonly type: "back" }
  | { readonly type: "goTo"; readonly step: string }
  | { readonly type: "reset"; readonly answers?: FormAnswers };

export interface QuestionnaireForm {
  readonly definition: FormDefinition;
  /** The version's generated schema. */
  readonly schema: FormJsonSchema;
}

/** The state before the first answer. */
export function initialQuestionnaire(
  form: QuestionnaireForm,
  answers: FormAnswers = {},
): QuestionnaireState {
  const first =
    visibleSteps(form.definition, answers)[0] ?? form.definition.steps[0];

  return { step: first?.key ?? "", answers, completed: [], issues: [] };
}

/** The step on screen, or the nearest visible one before it when an answer hid it. */
function stepAfterAnswer(
  form: QuestionnaireForm,
  step: string,
  answers: FormAnswers,
): string {
  const visible = new Set(
    visibleSteps(form.definition, answers).map((item) => item.key),
  );

  if (visible.has(step)) {
    return step;
  }

  const order = form.definition.steps.map((item) => item.key);
  const before = order.slice(0, Math.max(order.indexOf(step), 0)).toReversed();

  return (
    before.find((key) => visible.has(key)) ??
    order.find((key) => visible.has(key)) ??
    step
  );
}

/**
 * The questionnaire as a reducer: answers, the current step and the steps
 * done. `next` checks the step's fields against the version's schema and
 * stays put with `issues` when one fails; hidden steps are skipped.
 */
export function questionnaireReducer(
  form: QuestionnaireForm,
  state: QuestionnaireState,
  action: QuestionnaireAction,
): QuestionnaireState {
  const steps = visibleSteps(form.definition, state.answers);
  const index = steps.findIndex((step) => step.key === state.step);

  switch (action.type) {
    case "answer": {
      const answers = { ...state.answers };

      if (action.value === undefined) {
        delete answers[action.key];
      } else {
        answers[action.key] = action.value;
      }

      const issues = state.issues.filter(
        (issue) => issue.path?.[0] !== action.key,
      );

      return {
        ...state,
        step: stepAfterAnswer(form, state.step, answers),
        answers,
        issues,
      };
    }

    case "next": {
      const current = steps[index];

      if (current === undefined) {
        return state;
      }

      const issues = stepIssues(form.schema, current, state.answers);

      if (issues.length > 0) {
        return { ...state, issues };
      }

      const completed = state.completed.includes(current.key)
        ? state.completed
        : [...state.completed, current.key];

      const following = steps[index + 1];

      return {
        ...state,
        step: following?.key ?? current.key,
        completed,
        issues: [],
      };
    }

    case "back": {
      const previous = steps[index - 1];

      return previous === undefined
        ? state
        : { ...state, step: previous.key, issues: [] };
    }

    case "goTo": {
      const target = steps.findIndex((step) => step.key === action.step);

      const reachable =
        target !== -1 &&
        steps
          .slice(0, target)
          .every((step) => state.completed.includes(step.key));

      return reachable ? { ...state, step: action.step, issues: [] } : state;
    }

    case "reset": {
      return initialQuestionnaire(form, action.answers);
    }

    default: {
      const never: never = action;

      return never;
    }
  }
}

export interface QuestionnaireStepView {
  readonly key: string;
  readonly title?: string;
  readonly description?: string;
  readonly fields: readonly FormField[];
  readonly completed: boolean;
  readonly active: boolean;
}

/** The visible steps with their status, in the shape a Stepper renders. */
export function questionnaireSteps(
  form: QuestionnaireForm,
  state: QuestionnaireState,
): readonly QuestionnaireStepView[] {
  return visibleSteps(form.definition, state.answers).map((step) => ({
    key: step.key,
    ...(step.title === undefined ? {} : { title: step.title }),
    ...(step.description === undefined
      ? {}
      : { description: step.description }),
    fields: visibleFields(step, state.answers),
    completed: state.completed.includes(step.key),
    active: step.key === state.step,
  }));
}

/** The pruned answers, or every issue when the whole form does not pass. */
export function finishQuestionnaire(
  form: QuestionnaireForm,
  state: QuestionnaireState,
):
  | { readonly ok: true; readonly answers: FormAnswers }
  | { readonly ok: false; readonly issues: readonly ValidationIssue[] } {
  const answers = pruneAnswers(form.definition, state.answers);
  const issues = validateAnswers(form.schema, answers);

  return issues.length === 0 ? { ok: true, answers } : { ok: false, issues };
}
