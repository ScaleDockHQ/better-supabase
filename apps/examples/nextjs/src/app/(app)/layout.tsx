import type { ReactNode } from "react";

import Link from "next/link";
import { Suspense } from "react";

import { UnreadBadge } from "@/features/inbox/components/unread-badge";
import { AppNav } from "@/features/navigation/components/app-nav";
import { SideNavSkeleton } from "@/features/navigation/components/side-nav";
import {
  UserMenu,
  UserMenuSkeleton,
} from "@/features/user/components/user-menu";

/**
 * Synchronous on purpose: the header, sidebar frame and skeletons are the
 * static shell. Everything that reads the session streams in behind its own
 * `<Suspense>` boundary.
 */
export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    <div className="app">
      <header>
        <Link href="/">better-supabase</Link>
        <UnreadBadge />
        <Suspense fallback={<UserMenuSkeleton />}>
          <UserMenu />
        </Suspense>
      </header>
      <aside>
        <Suspense fallback={<SideNavSkeleton />}>
          <AppNav />
        </Suspense>
      </aside>
      <main>{children}</main>
    </div>
  );
}
