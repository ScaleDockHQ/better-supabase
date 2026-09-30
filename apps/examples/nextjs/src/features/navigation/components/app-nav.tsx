import { SessionProvider } from "better-supabase/react";

import { getSession } from "@/features/user/user-queries";

import { SideNav } from "./side-nav";

/**
 * Render inside `<Suspense>`: the session promise is created here, behind
 * the boundary, and resolved by `useSession()` in the client menu.
 */
export function AppNav() {
  return (
    <SessionProvider sessionPromise={getSession()}>
      <SideNav />
    </SessionProvider>
  );
}
