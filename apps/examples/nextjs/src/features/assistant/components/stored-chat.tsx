import { notFound } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";

import { getStoredChat } from "../assistant-queries";
import { durableAvailable } from "../assistant-server";
import { AssistantChat } from "./assistant-chat";

/** Render inside `<Suspense>`: reads the `id` param and the stored branch. */
export async function StoredChat({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const chat = await getStoredChat(id);
  if (chat === undefined) notFound();
  return (
    <AssistantChat
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
