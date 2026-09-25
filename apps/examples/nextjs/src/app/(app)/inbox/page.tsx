import { Panel } from '@/components/ui/panel';

export const instant = true;

export default function InboxPage() {
  return (
    <>
      <h1>Inbox</h1>
      <Panel>
        <p>Every signed-in user sees the inbox.</p>
      </Panel>
    </>
  );
}
