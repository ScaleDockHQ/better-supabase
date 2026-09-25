'use client';

import { useRouter } from 'next/navigation';
import { useTransition } from 'react';

import { useSupabase } from '@/lib/hooks';

import { sessionChanged } from '../user-actions';

export function SignOutButton() {
  const supabase = useSupabase();
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  return (
    <button
      type="button"
      disabled={pending}
      onClick={() =>
        startTransition(async () => {
          await supabase.auth.signOut();
          await sessionChanged();
          router.push('/login');
        })
      }
    >
      Sign out
    </button>
  );
}
