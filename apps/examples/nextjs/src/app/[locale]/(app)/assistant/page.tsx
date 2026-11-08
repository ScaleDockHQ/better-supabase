import type { JsonRenderSpec } from "better-supabase/json-render";

import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ChatList,
  ChatListSkeleton,
} from "@/features/assistant/components/chat-list";
import { NewChat } from "@/features/assistant/components/new-chat";
import { SpecViewLazy } from "@/features/assistant/components/spec-view-lazy";
import { StoredChatSkeleton } from "@/features/assistant/components/stored-chat";

const SAMPLE_SPEC: JsonRenderSpec = {
  root: "stack",
  elements: {
    stack: { type: "Stack", children: ["title", "body"] },
    title: { type: "Heading", props: { text: "Specs in chat" } },
    body: {
      type: "Text",
      props: {
        text: "A model can stream UI as a json-render spec; this card renders one.",
      },
    },
  },
};

// The heading and the sample card paint before the chats stream in.
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
      <SpecViewLazy spec={SAMPLE_SPEC} />
      <div data-recipe="chat-with-history">
        <Suspense fallback={<StoredChatSkeleton />}>
          <NewChat />
        </Suspense>
      </div>
      <Suspense fallback={<ChatListSkeleton />}>
        <ChatList />
      </Suspense>
    </>
  );
}
