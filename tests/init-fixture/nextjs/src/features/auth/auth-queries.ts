import 'server-only';

import { bsb } from '../../lib/supabase/server';

/** The signed-in user as plain data, kept in the App Shell for five minutes. */
export async function getUser() {
  'use cache: private';

  return bsb.user();
}
