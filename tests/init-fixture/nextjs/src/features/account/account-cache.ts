import { tagFor } from 'better-supabase/next';

/** The tag of one user's account entry; `updateTag` it after a write. */
export const accountTag = (userId: string): string =>
  tagFor('account', userId);
