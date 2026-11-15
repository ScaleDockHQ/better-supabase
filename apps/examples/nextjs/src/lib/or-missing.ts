import type { Result } from "better-supabase";

/**
 * The row a block `get` read, `undefined` for a `not_found` error (the page
 * then shows its not-found state), and the error thrown for any other.
 */
export function orMissing<T>(result: Result<T>): T | undefined {
  if (result.ok) {
    return result.data;
  }

  if (result.error.kind === "not_found") {
    return undefined;
  }

  throw new Error(result.error.message);
}
