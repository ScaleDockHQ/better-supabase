import type { ReactNode } from 'react';

import { AuthGate } from 'better-supabase/next/auth-gate';

import { getUser } from '../auth-queries';

export function AppAuthGate({
  children,
  fallback,
}: {
  children: ReactNode;
  fallback: ReactNode;
}) {
  return (
    <AuthGate user={getUser} fallback={fallback} redirect="/sign-in">
      {children}
    </AuthGate>
  );
}
