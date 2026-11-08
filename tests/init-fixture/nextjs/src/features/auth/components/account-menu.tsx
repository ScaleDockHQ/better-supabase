'use client';

import { useUser } from 'better-supabase/next/auth-gate';

import { signOutAction } from '../auth-actions';

export function AccountMenu() {
  const user = useUser();

  return (
    <form action={signOutAction}>
      <span>{user?.email}</span>
      <button type="submit">Sign out</button>
    </form>
  );
}
