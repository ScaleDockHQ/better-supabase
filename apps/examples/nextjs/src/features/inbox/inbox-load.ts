import type { DbError } from "better-supabase";

type Loaded<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: DbError };

/** The loaders of `useInbox` and `useConversation` reject on an error. */
export function unwrap<T>(result: Loaded<T>): T {
  if (!result.ok)
    throw new Error(result.error.message, { cause: result.error });
  return result.data;
}
