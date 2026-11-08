import type { ReactNode } from 'react';

import { AppShellSkeleton } from '../../components/app-shell-skeleton';
import { AppAuthGate } from '../../features/auth/components/app-auth-gate';

/** The layout stays synchronous: the gate streams the signed-in user. */
export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    <AppAuthGate fallback={<AppShellSkeleton />}>{children}</AppAuthGate>
  );
}
