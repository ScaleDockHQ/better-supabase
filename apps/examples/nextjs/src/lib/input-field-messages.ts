import type { DbError } from "better-supabase";

import { fieldErrorsOf } from "better-supabase/react";

/** The first message per top-level input, as `fieldErrorsOf` returns it. */
export type InputFieldMessages = ReturnType<typeof fieldErrorsOf>;

/**
 * The message for each top-level input of a failed action: the issues of a
 * `validation` error and the `fields` of an `invalid_input` error (ADR 0709),
 * so a form places both next to the input.
 */
export function inputFieldMessages(
  error: DbError | undefined,
): InputFieldMessages {
  if (error?.kind !== "invalid_input") {
    return fieldErrorsOf(error);
  }

  const messages = new Map<string, string>();

  for (const field of error.fields ?? []) {
    const [key] = field.path;

    if (key !== undefined && !messages.has(String(key))) {
      messages.set(String(key), field.message);
    }
  }

  return Object.fromEntries(messages);
}
