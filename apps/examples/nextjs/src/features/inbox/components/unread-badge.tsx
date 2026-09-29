'use client';

import { type LiveCountSeed, useLiveCount } from 'better-supabase/react';
import Link from 'next/link';

import { unreadSpec } from '../inbox-specs';

/**
 * The header badge. Part of the static shell, so it counts from the browser
 * (one HEAD request) instead of adding a database call to every page.
 */
export function UnreadBadge() {
  const { count, status } = useLiveCount(unreadSpec);
  return (
    <Link
      href="/inbox"
      className="unread"
      data-testid="unread-badge"
      data-status={status}
    >
      Inbox <span data-testid="unread-count">{count ?? '–'}</span>
    </Link>
  );
}

/** The inbox summary: renders the server's count, then stays live. */
export function UnreadSummary({ seed }: { seed: LiveCountSeed }) {
  const { count } = useLiveCount(seed);
  return (
    <p data-testid="unread-summary">
      {count === undefined ? 'Counting…' : `${String(count)} unread`}
    </p>
  );
}
