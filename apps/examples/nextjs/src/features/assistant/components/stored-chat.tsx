import { notFound } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";

import { getStoredChat } from "../assistant-queries";
import { durableAvailable } from "../assistant-server";
import { AssistantChatLazy } from "./assistant-chat-lazy";

/** Render inside `<Suspense>`: reads the `id` param and the stored branch. */
export async function StoredChat({ id }: { id: string }) {
  const chat = await getStoredChat(id);

  if (chat === undefined) {
    notFound();
  }

  return (
    <AssistantChatLazy
      id={id}
      messages={chat.messages}
      streaming={chat.streaming}
      initialMode={chat.durable ? "durable" : "standard"}
      durableAvailable={durableAvailable()}
    />
  );
}

export function StoredChatSkeleton() {
  return <Skeleton className="min-h-96 w-full rounded-xl" />;
}
