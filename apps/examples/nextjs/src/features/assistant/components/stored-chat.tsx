import { notFound } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";

import { getChatMessages } from "../assistant-queries";
import { AssistantChat } from "./assistant-chat";

/** Render inside `<Suspense>`: reads the `id` param and the stored branch. */
export async function StoredChat({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const messages = await getChatMessages(id);
  if (messages === undefined) notFound();
  return <AssistantChat id={id} messages={messages} />;
}

export function StoredChatSkeleton() {
  return <Skeleton className="min-h-96 w-full rounded-xl" />;
}
