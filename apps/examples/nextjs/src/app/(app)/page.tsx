import { Panel } from '@/components/ui/panel';

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
    </>
  );
}
