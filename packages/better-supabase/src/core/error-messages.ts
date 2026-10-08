import type { DbError, DbErrorKind, DbErrorOf } from "./errors.ts";

/**
 * A message for every `DbError` kind: a string, or a function of the error.
 * Leaving a kind out is a type error, so a new kind can't fall through.
 */
export type ErrorMessages = {
  readonly [K in DbErrorKind]: string | ((error: DbErrorOf<K>) => string);
};

/**
 * Turns an error into the sentence to show the user. Build it where your
 * translations are, e.g. inside a hook that has `t`.
 *
 * ```ts
 * const message = createErrorMessages({
 *   unauthorized: t('Sign in again to continue.'),
 *   raised: (error) => error.message,
 *   // ...every other kind
 * });
 * toast.error(message(result.error));
 * ```
 */
export function createErrorMessages(
  messages: ErrorMessages,
): (error: DbError) => string {
  return (error) => {
    // SAFETY: the mapped type pairs each kind with a formatter for that kind's error.
    const message = messages[error.kind] as
      | string
      | ((error: DbError) => string);
    return typeof message === "string" ? message : message(error);
  };
}
