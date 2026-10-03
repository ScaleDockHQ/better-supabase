"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BetterSupabaseProvider } from "better-supabase/react";
import { type ReactNode, useState } from "react";

import { bs } from "../lib/supabase/client";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <QueryClientProvider client={queryClient}>
      <BetterSupabaseProvider client={bs} queryClient={queryClient}>
        {children}
      </BetterSupabaseProvider>
    </QueryClientProvider>
  );
}
