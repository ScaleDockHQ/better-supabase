"use client";

import type { ReactNode } from "react";

import { use } from "react";

// Native `Temporal` ships in current Chrome and Firefox; Safari and Node 24
// do not have it. Only a browser without it fetches the polyfill chunk, and the
// import starts when this module loads so it overlaps hydration. Node installs
// the global in `lib/supabase/app.ts`, so the server never waits.
const polyfill: Promise<unknown> | undefined =
  typeof window !== "undefined" && !("Temporal" in globalThis)
    ? import("temporal-polyfill/global")
    : undefined;

function Gate({ children }: { children: ReactNode }): ReactNode {
  if (polyfill !== undefined) {
    use(polyfill);
  }

  return children;
}

/**
 * Holds its children until `Temporal` exists. Wrap it in a `<Suspense>`: the
 * server HTML stays on screen while a browser without `Temporal` loads the
 * polyfill, and the subtree hydrates once it arrives.
 */
export function TemporalGate({ children }: { children: ReactNode }) {
  return <Gate>{children}</Gate>;
}
