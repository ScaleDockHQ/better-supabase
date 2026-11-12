import type { DbError } from "better-supabase";

/**
 * The block hint messages, loaded on demand: they are 110 KB of text that no
 * route's first-load JavaScript should carry.
 */
export async function loadBlockErrorMessage(): Promise<
  (error: DbError) => string | undefined
> {
  const { blockErrorMessage } = await import("better-supabase/blocks/messages");

  return (error) => blockErrorMessage(error);
}
