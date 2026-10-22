import type { SingleKeyEntry } from "@supabase/middleware";
import type { SupabaseClient } from "@supabase/supabase-js";

import { defineMiddleware } from "@supabase/middleware";

import type { Db } from "../../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";

/**
 * Entry contributing `ctx.db`: repositories over PostgREST as the caller (RLS
 * applies), from `ctx.bsb`. Reads go to the read replica when one is
 * configured.
 */
export function withDb<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  B,
>(): SingleKeyEntry<
  "db",
  { readonly bsb: { readonly db: Db<M, F, E, SupabaseClient, B> } },
  Db<M, F, E, SupabaseClient, B>
> {
  return defineMiddleware<
    "db",
    undefined,
    { readonly bsb: { readonly db: Db<M, F, E, SupabaseClient, B> } },
    Db<M, F, E, SupabaseClient, B>
  >({
    key: "db",
    run: () => (_request, ctx) => Promise.resolve({ db: ctx.bsb.db }),
  })();
}
