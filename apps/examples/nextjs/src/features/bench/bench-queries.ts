import type { SessionHandle } from "better-supabase/next";

import "server-only";

import { bsb } from "@/lib/supabase/server";

/** One private scope that resolves the caller and returns who it is. */
export async function readScope(index: number): Promise<string> {
  "use cache: private";

  const ctx = await bsb.cached();

  return `${index}:${ctx.session.kind === "user" ? ctx.session.user.id : "-"}`;
}

/** The same scope, resolved from the handle the page parked. */
export async function readScopeFromHandle(
  index: number,
  session: SessionHandle,
): Promise<string> {
  "use cache: private";

  const ctx = await bsb.cached({ session });

  return `${index}:${ctx.session.kind === "user" ? ctx.session.user.id : "-"}`;
}
