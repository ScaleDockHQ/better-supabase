"use client";

import { useState } from "react";

import type { EntityForm, EntityFormValues } from "../records/entity-form.ts";

export interface UseEntityFormOptions<T> {
  /** The values the form starts with, by field key. */
  readonly initial?: Readonly<Record<string, unknown>>;
  /** Receives the block input and the custom values once they validate. */
  readonly onSubmit: (values: EntityFormValues<T>) => unknown;
}

/** What `useEntityForm` returns. */
export interface EntityFormState {
  readonly values: Readonly<Record<string, unknown>>;
  /** One message per field key, from the last submit. */
  readonly errors: Readonly<Record<string, string>>;
  /** True while `onSubmit` runs. */
  readonly pending: boolean;
  set(key: string, value: unknown): void;
  /** Validates, then calls `onSubmit`; pass it to a form's `onSubmit`. */
  submit(event?: { preventDefault(): void }): Promise<void>;
  reset(): void;
}

const NO_VALUES: Readonly<Record<string, unknown>> = {};
const NO_ERRORS: Readonly<Record<string, string>> = {};

/**
 * The state of a form from `entityForm`: the values by key, the errors of the
 * last submit, and `submit`, which validates with the entity schema before it
 * calls `onSubmit`.
 *
 * ```tsx
 * const state = useEntityForm(form, {
 *   onSubmit: (values) => create(values),
 * });
 * <form onSubmit={state.submit}>…</form>;
 * ```
 */
export function useEntityForm<T>(
  form: EntityForm<T>,
  options: UseEntityFormOptions<T>,
): EntityFormState {
  const initial = options.initial ?? NO_VALUES;
  const [values, setValues] = useState(initial);

  const [errors, setErrors] =
    useState<Readonly<Record<string, string>>>(NO_ERRORS);

  const [pending, setPending] = useState(false);

  return {
    values,
    errors,
    pending,
    set: (key, value) => {
      setValues((current) => ({ ...current, [key]: value }));
    },
    submit: async (event) => {
      event?.preventDefault();
      setPending(true);
      const result = await form.validate(values);

      if (!result.ok) {
        setErrors(result.errors);
        setPending(false);

        return;
      }

      setErrors(NO_ERRORS);
      await Promise.resolve(
        options.onSubmit({ input: result.input, custom: result.custom }),
      ).finally(() => {
        setPending(false);
      });
    },
    reset: () => {
      setValues(initial);
      setErrors(NO_ERRORS);
    },
  };
}
