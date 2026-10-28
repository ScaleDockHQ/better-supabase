import type { AnyEntry, Contributions } from "@supabase/middleware";

import { cookies, headers } from "next/headers.js";

import type { ToNextActionOptions } from "../bridges/next.ts";
import type { Validated } from "../bridges/shared.ts";

import { nextAction } from "../bridges/next.ts";

/**
 * Runs an entry array around a Server Action. The entries see a request built
 * from `headers()` (the session cookie included), cookies they set go through
 * `cookies().set`, and the action gets their contributions as `ctx`. When an
 * entry answers first (a 401 from `withRequiredClaims`), the call throws
 * `NextActionRejected` with that response.
 *
 * ```ts
 * "use server";
 * export const addNote = toNextAction(
 *   [withRequiredClaims(), withSupabaseClient()],
 *   async (ctx, body: string) =>
 *     ctx.supabase.from("notes").insert({ body }),
 * );
 * ```
 */
export function toNextAction<
  const Entries extends readonly AnyEntry[],
  Args extends unknown[],
  Result,
>(
  entries: Entries & Validated<Entries>,
  action: (ctx: Contributions<Entries>, ...args: Args) => Promise<Result>,
  options: ToNextActionOptions = {},
): (...args: Args) => Promise<Result> {
  return nextAction(
    entries,
    action,
    {
      headers: async () => new Headers(await headers()),
      setCookie: async ({ name, value, ...attributes }) => {
        (await cookies()).set(name, value, attributes);
      },
    },
    options,
  );
}
