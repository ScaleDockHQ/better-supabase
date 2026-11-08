"use client";

import type { ReactNode } from "react";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BetterSupabaseProvider } from "better-supabase/react";
import { useState } from "react";

import { bsb } from "../lib/supabase/client";

/**
 * The browser client and the query cache. Only the `(app)` layout and the few
 * public routes that run hooks render it, so the sign-in routes ship neither
 * the client, the data engine nor `@tanstack/query-core`.
 */
export function DataProviders({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <QueryClientProvider client={queryClient}>
      <BetterSupabaseProvider client={bsb} queryClient={queryClient}>
        {children}
      </BetterSupabaseProvider>
    </QueryClientProvider>
  );
}
