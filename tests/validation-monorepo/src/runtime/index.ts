import type { EdgeOptions } from "better-supabase/edge";
import type { AuthSession, ServerContext } from "better-supabase/server";

import { defineSupabase } from "better-supabase";
import { createEdge } from "better-supabase/edge";
import { toSession } from "better-supabase/server";

import type { Functions, Models } from "./generated.ts";

import { schema } from "./generated.ts";

/**
 * The one `defineSupabase` in the monorepo. Domain packages never import
 * `./generated.ts`.
 */
export const betterSupabase = defineSupabase(schema);

/** The request context every domain package receives. */
export type AppContext = ServerContext<Models, Functions, unknown>;

/** The typed repositories, for domain package signatures. */
export type Db = AppContext["db"];

/** Who calls: the user, and the OAuth client or agent acting for them. */
export function sessionOf(ctx: AppContext): AuthSession {
  return toSession(ctx.auth);
}

export function createRuntime(options: EdgeOptions) {
  return createEdge(betterSupabase, options);
}

export type Runtime = ReturnType<typeof createRuntime>;
