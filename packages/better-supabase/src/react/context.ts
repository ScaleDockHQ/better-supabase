import type { QueryClient } from "@tanstack/query-core";

import { type Context, createContext } from "react";

import type { ClientLike } from "../bindings/client.ts";

export interface ContextValue {
  readonly client: ClientLike;
  readonly queryClient: QueryClient | undefined;
}

/**
 * The provider's client. It lives in its own module so the block hooks read
 * it without bundling the rest of the React bindings.
 */
export const ClientContext: Context<ContextValue | null> =
  createContext<ContextValue | null>(null);
