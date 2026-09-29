import { Panel, PanelSkeleton } from '@/components/ui/panel';

import { getWorkspaceSummary } from '../dashboard-queries';

export async function WorkspaceSummary() {
  const summary = await getWorkspaceSummary();
  if (!summary) return null;
  return (
    <Panel>
      <dl className="summary" data-testid="workspace-summary">
        <dt>Customers</dt>
        <dd>{summary.customers}</dd>
        <dt>Active</dt>
        <dd>{summary.active}</dd>
        <dt>Added by you</dt>
        <dd>{summary.mine}</dd>
        <dt>Latest note</dt>
        <dd>{summary.latestNote?.body ?? 'None yet'}</dd>
      </dl>
    </Panel>
  );
}

export function WorkspaceSummarySkeleton() {
  return <PanelSkeleton />;
}
