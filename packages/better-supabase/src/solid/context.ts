import type { QueryClient } from "@tanstack/query-core";

import {
  type Accessor,
  type Context as SolidContext,
  createContext,
  useContext as useSolidContext,
} from "solid-js";

import type { AuthSession } from "../auth/view.ts";
import type { ClientLike } from "../bindings/client.ts";
import type { AuthSnapshot } from "../client/index.ts";

export interface Context {
  readonly client: ClientLike;
  readonly queryClient: QueryClient | undefined;
  readonly auth: Accessor<AuthSnapshot>;
  readonly session: Accessor<AuthSession | undefined> | undefined;
}

export const ClientContext: SolidContext<Context | undefined> = createContext<
  Context | undefined
>();

/** What `<BetterSupabaseProvider>` provides. */
export function useContext(): Context {
  const context = useSolidContext(ClientContext);
  if (!context) {
    throw new Error(
      "better-supabase: wrap your app in <BetterSupabaseProvider client={bs}>",
    );
  }
  return context;
}
