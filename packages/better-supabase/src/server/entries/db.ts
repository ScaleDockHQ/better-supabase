import type { SupabaseClient } from "@supabase/supabase-js";

import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { Db } from "../../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";

/**
 * Entry contributing `ctx.db`: repositories over PostgREST as the caller
 * (RLS applies), from `ctx.bs`. Reads go to the read replica when one is
 * configured.
 */
export function withDb<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
>(): SingleKeyEntry<
  "db",
  { readonly bs: { readonly db: Db<M, F, E, SupabaseClient> } },
  Db<M, F, E, SupabaseClient>
> {
  return defineMiddleware<
    "db",
    undefined,
    { readonly bs: { readonly db: Db<M, F, E, SupabaseClient> } },
    Db<M, F, E, SupabaseClient>
  >({
    key: "db",
    run: () => (_request, ctx) => Promise.resolve({ db: ctx.bs.db }),
  })();
}
