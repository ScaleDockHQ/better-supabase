import { useExtracted } from "next-intl";

import { PageHeader } from "@/components/page-header";
import { ChatView } from "@/features/chat/components/chat-view";

export const instant = true;

export default function ChatPage() {
  const t = useExtracted("chat");

  return (
    <>
      <PageHeader
        title={t("Chat")}
        description={t(
          "Channels for your team, with threads, mentions and files, kept live over Realtime.",
        )}
      />
      <div data-recipe="channel-sidebar">
        <ChatView />
      </div>
    </>
  );
}
