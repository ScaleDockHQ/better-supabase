import { defineSupabase } from "better-supabase";
import {
  type AuthSession,
  type ServerContext,
  toSession,
} from "better-supabase/server";

import { type Functions, type Models, schema } from "./generated";

/** The one `defineSupabase` in the monorepo. Domain packages never import `./generated`. */
export const betterSupabase = defineSupabase(schema);

/** The request context every domain package receives. */
export type AppContext = ServerContext<Models, Functions, unknown>;

/** The typed repositories, for domain package signatures. */
export type Db = AppContext["db"];

/** Who calls: the user, and the OAuth client or agent acting for them. */
export function sessionOf(ctx: AppContext): AuthSession {
  return toSession(ctx.auth);
}
