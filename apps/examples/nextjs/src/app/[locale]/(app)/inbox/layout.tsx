import type { ReactNode } from "react";

import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { ChannelSimulatorLazy } from "@/features/inbox/components/channel-simulator-lazy";
import {
  InboxQueue,
  InboxQueueSkeleton,
} from "@/features/inbox/components/inbox-queue";
import { InboxShell } from "@/features/inbox/components/inbox-shell";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function InboxLayout({ children }: { children: ReactNode }) {
  const t = useExtracted("inbox");

  return (
    <>
      <PageHeader
        title={t("Inbox")}
        description={t(
          "One queue for the web widget, email, Slack and WhatsApp, kept live over Realtime.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="inbox.manage">
              <ChannelSimulatorLazy />
            </PermissionGate>
          </Suspense>
        }
      />
      <InboxShell
        queue={
          <Suspense fallback={<InboxQueueSkeleton />}>
            <InboxQueue />
          </Suspense>
        }
      >
        {children}
      </InboxShell>
    </>
  );
}
