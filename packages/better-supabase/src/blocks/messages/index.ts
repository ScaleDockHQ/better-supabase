import type { DbError } from "../../core/errors.ts";

import { BLOCK_HINT_MESSAGES } from "./hint-messages.generated.ts";

export { BLOCK_HINT_MESSAGES } from "./hint-messages.generated.ts";

/**
 * Words a code in the user's language. Return `undefined` to keep `english`,
 * the default message. With next-intl: `(code, english) => t.has(code) ?
 * t(code) : english`.
 */
export type TranslateHint = (
  code: string,
  english: string,
) => string | undefined;

function isKnownHint(code: string): code is keyof typeof BLOCK_HINT_MESSAGES {
  return Object.hasOwn(BLOCK_HINT_MESSAGES, code);
}

/** The message of a hint code, or `undefined` when no block raises it. */
export function hintMessage(
  code: string,
  translate?: TranslateHint,
): string | undefined {
  if (!isKnownHint(code)) {
    return undefined;
  }

  const english = BLOCK_HINT_MESSAGES[code];

  return translate?.(code, english) ?? english;
}

/**
 * The message for a block error: the one for its hint code, or `undefined` for
 * an error without a known code (then use `error.message` or your own wording
 * of the error's kind).
 */
export function blockErrorMessage(
  error: DbError,
  translate?: TranslateHint,
): string | undefined {
  return error.hint === undefined
    ? undefined
    : hintMessage(error.hint, translate);
}

/**
 * The messages of an `invalid_input` error by field, keyed by the dotted path
 * (`lines.0.quantity`), for a form library's `setError`. A field's code is
 * looked up first, then its own English `message` is used. The first message
 * for a path wins.
 */
export function fieldMessages(
  error: DbError,
  translate?: TranslateHint,
): Readonly<Record<string, string>> {
  if (error.kind !== "invalid_input" || error.fields === undefined) {
    return {};
  }

  const messages: Record<string, string> = {};

  for (const field of error.fields) {
    const path = field.path.join(".");

    if (!Object.hasOwn(messages, path)) {
      messages[path] = translate?.(field.code, field.message) ?? field.message;
    }
  }

  return messages;
}
