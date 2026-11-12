import { Suspense } from "react";

import {
  ConversationDetail,
  ConversationDetailSkeleton,
} from "@/features/inbox/components/conversation-detail";

// A navigation here keeps the queue and shows the thread's skeleton at once;
// the thread and the contact context stream in.
export const instant = true;

export default function ConversationPage({
  params,
}: PageProps<"/[locale]/inbox/[conversation]">) {
  return (
    <Suspense fallback={<ConversationDetailSkeleton />}>
      {params.then(({ conversation }) => (
        <ConversationDetail id={conversation} />
      ))}
    </Suspense>
  );
}
