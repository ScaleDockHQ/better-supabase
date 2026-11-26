'use server';

import { createAuthFlows } from 'better-supabase/next/sign-in';

import { bsb } from '../../lib/supabase/server';

export async function signOutAction(): Promise<void> {
  await createAuthFlows(bsb).signOut({ next: '/sign-in' });
}
