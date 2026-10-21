import type { QueryClient } from "@tanstack/query-core";

import {
  getCurrentInstance,
  inject,
  type InjectionKey,
  onMounted,
  type Ref,
} from "vue";

import type { ClientLike } from "../bindings/client.ts";
import type { AuthSnapshot } from "../client/index.ts";

export interface Context {
  readonly client: ClientLike;
  readonly queryClient: QueryClient | undefined;
  readonly auth: Readonly<Ref<AuthSnapshot>>;
}

export const CLIENT: InjectionKey<Context> = Symbol("better-supabase");

/** What `app.use(betterSupabase(bs))` provides. */
export function useContext(): Context {
  const context = inject(CLIENT, null);

  if (!context) {
    throw new Error(
      "better-supabase: install the plugin with app.use(betterSupabase(bs))",
    );
  }

  return context;
}

/**
 * Runs `start` on mount in a component, at once elsewhere (an effect scope),
 * and never during server rendering.
 */
export function onClient(start: () => void): void {
  if (getCurrentInstance()) {
    onMounted(start);
  } else {
    start();
  }
}
