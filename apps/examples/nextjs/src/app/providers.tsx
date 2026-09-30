"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BetterSupabaseProvider } from "better-supabase/react";
import { type ReactNode, useState } from "react";

import { browser } from "../lib/supabase.browser";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <QueryClientProvider client={queryClient}>
      <BetterSupabaseProvider browser={browser} queryClient={queryClient}>
        {children}
      </BetterSupabaseProvider>
    </QueryClientProvider>
  );
}
