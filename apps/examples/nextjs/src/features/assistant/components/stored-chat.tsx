import { notFound } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";

import { getModels, getStoredChat } from "../assistant-queries";
import { durableAvailable } from "../assistant-server";
import { AssistantChatLazy } from "./assistant-chat-lazy";
import { ChatActions } from "./chat-actions";

/** Render inside `<Suspense>`: reads the `id` param and the stored branch. */
export async function StoredChat({ id }: { id: string }) {
  const [chat, models] = await Promise.all([getStoredChat(id), getModels()]);

  if (chat === undefined) {
    notFound();
  }

  return (
    <>
      <ChatActions chatId={id} title={chat.title} pinned={chat.pinned} />
      <AssistantChatLazy
        key={chat.leafId}
        id={id}
        messages={chat.messages}
        streaming={chat.streaming}
        initialMode={chat.durable ? "durable" : "standard"}
        durableAvailable={durableAvailable()}
        models={models}
        initialModel={chat.model}
        branches={chat.branches}
      />
    </>
  );
}

export function StoredChatSkeleton() {
  return <Skeleton className="min-h-96 w-full rounded-xl" />;
}
