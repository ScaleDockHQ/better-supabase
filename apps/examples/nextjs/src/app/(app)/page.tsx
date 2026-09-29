import { Suspense } from 'react';

import { Panel } from '@/components/ui/panel';
import {
  WorkspaceSummary,
  WorkspaceSummarySkeleton,
} from '@/features/dashboard/components/workspace-summary';

export const instant = true;

export default function DashboardPage() {
  return (
    <>
      <h1>Dashboard</h1>
      <Panel>
        <p>
          Everything outside a Suspense boundary is part of the static shell, so
          this page renders instantly on every navigation.
        </p>
      </Panel>
      <Suspense fallback={<WorkspaceSummarySkeleton />}>
        <WorkspaceSummary />
      </Suspense>
    </>
  );
}
