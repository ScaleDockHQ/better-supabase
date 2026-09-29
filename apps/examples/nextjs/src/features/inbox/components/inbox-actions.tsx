'use client';

import { useTransition } from 'react';

import { markAllRead, notifyMe } from '../inbox-actions';

export function InboxActions() {
  const [pending, start] = useTransition();
  return (
    <p>
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          start(async () => {
            await notifyMe({ title: 'Hello from the inbox' });
          })
        }
      >
        Notify me
      </button>{' '}
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          start(async () => {
            await markAllRead({});
          })
        }
      >
        Mark all read
      </button>
    </p>
  );
}
