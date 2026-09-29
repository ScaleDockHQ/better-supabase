import { Suspense } from 'react';

import { Panel } from '@/components/ui/panel';
import { InboxActions } from '@/features/inbox/components/inbox-actions';
import { UnreadCount } from '@/features/inbox/components/unread-count';

export const instant = true;

export default function InboxPage() {
  return (
    <>
      <h1>Inbox</h1>
      <Panel>
        <p>Every signed-in user sees the inbox.</p>
        <Suspense fallback={<p className="skeleton" />}>
          <UnreadCount />
        </Suspense>
        <InboxActions />
      </Panel>
    </>
  );
}
