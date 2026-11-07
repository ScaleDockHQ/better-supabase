'use server';

import { bsb } from '../../lib/supabase/server';

export async function signOutAction(): Promise<void> {
  await bsb.signOut({ next: '/sign-in' });
}
