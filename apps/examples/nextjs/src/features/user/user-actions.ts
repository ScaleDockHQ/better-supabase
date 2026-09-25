'use server';

import { refresh } from 'next/cache';

/**
 * Call after the browser client signs in or out. `refresh()` from a Server
 * Action clears the client router cache, including every private session
 * read, so the next render sees the new user.
 */
export async function sessionChanged(): Promise<void> {
  refresh();
}
