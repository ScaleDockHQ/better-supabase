import 'server-only';

import { bsb } from '../../lib/supabase/server';
import { accountTag } from './account-cache';

/** One account section of a user, kept until a write calls `updateTag`. */
export async function getAccountSection(userId: string, section: string) {
  'use cache: private';

  const { session } = await bsb.cached({
    life: 'max',
    tags: [accountTag(userId)],
  });

  return {
    section,
    email: session.kind === 'user' ? session.user.email : undefined,
  };
}
