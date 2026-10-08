import type { ReactNode } from "react";

/** Web: server loaders read as the caller, so the shell adds nothing. */
export function AppShell({ children }: { readonly children: ReactNode }) {
  return children;
}
