"use client";

import type { ReactNode } from "react";

import { NuqsAdapter } from "nuqs/adapters/next/app";

import { TooltipProvider } from "@/components/ui/tooltip";

/**
 * The providers every route needs. The data client and its query cache live in
 * `data-providers.tsx`, which only the routes that run hooks register.
 */
export function Providers({ children }: { children: ReactNode }) {
  return (
    <NuqsAdapter>
      <TooltipProvider>{children}</TooltipProvider>
    </NuqsAdapter>
  );
}
