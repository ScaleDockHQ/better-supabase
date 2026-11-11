import type { SessionHandle } from "better-supabase/next";

import "server-only";

import { bsbCore } from "@/lib/supabase/server-core";

/** One private scope that resolves the caller and returns who it is. */
export async function readScope(index: number): Promise<string> {
  "use cache: private";

  const ctx = await bsbCore.cached();

  return `${index}:${ctx.session.kind === "user" ? ctx.session.user.id : "-"}`;
}

/** The same scope, resolved from the handle the page parked. */
export async function readScopeFromHandle(
  index: number,
  session: SessionHandle,
): Promise<string> {
  "use cache: private";

  const ctx = await bsbCore.cached({ session });

  return `${index}:${ctx.session.kind === "user" ? ctx.session.user.id : "-"}`;
}
