import { getUnreadSeed } from '../inbox-queries';
import { UnreadSummary } from './unread-badge';

/**
 * Render inside `<Suspense>`: counts on the server with `next.liveCount`,
 * so the number is there on first paint and the client only refetches on
 * changes.
 */
export async function UnreadCount() {
  return <UnreadSummary seed={await getUnreadSeed()} />;
}
