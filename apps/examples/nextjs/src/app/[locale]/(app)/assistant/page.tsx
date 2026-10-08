import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ChatList,
  ChatListSkeleton,
} from "@/features/assistant/components/chat-list";
import { NewChat } from "@/features/assistant/components/new-chat";
import { StoredChatSkeleton } from "@/features/assistant/components/stored-chat";

export const instant = true;

export default function AssistantPage() {
  const t = useExtracted("assistant");
  return (
    <>
      <PageHeader
        title={t("Assistant")}
        description={t(
          "Chats on the ai-chat block. A reload resumes an answer that is still streaming.",
        )}
      />
      <Suspense fallback={<StoredChatSkeleton />}>
        <NewChat />
      </Suspense>
      <Suspense fallback={<ChatListSkeleton />}>
        <ChatList />
      </Suspense>
    </>
  );
}
