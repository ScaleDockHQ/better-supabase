import type { ReactNode } from "react";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BetterSupabaseProvider } from "better-supabase/react";
import { useState } from "react";

import { bsb } from "./lib/supabase/client";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <QueryClientProvider client={queryClient}>
      <BetterSupabaseProvider client={bsb} queryClient={queryClient}>
        {children}
      </BetterSupabaseProvider>
    </QueryClientProvider>
  );
}
