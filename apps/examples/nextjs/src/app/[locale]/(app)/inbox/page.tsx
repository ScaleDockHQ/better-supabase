import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  InboxList,
  InboxListSkeleton,
} from "@/features/inbox/components/inbox-list";

export default function InboxPage() {
  const t = useExtracted("inbox");

  return (
    <>
      <PageHeader
        title={t("Inbox")}
        description={t(
          "Customer conversations from the Help widget and chat channels, kept live over Realtime.",
        )}
      />
      <div data-recipe="inbox-threads">
        <Suspense fallback={<InboxListSkeleton />}>
          <InboxList />
        </Suspense>
      </div>
    </>
  );
}
