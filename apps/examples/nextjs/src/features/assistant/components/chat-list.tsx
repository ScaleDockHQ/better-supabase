import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getChatPage } from "../assistant-queries";
import { ChatTable } from "./chat-table";

/** Render inside `<Suspense>`: the filtered page of chats for the URL's state. */
export async function ChatList({ query }: { query: Promise<OpsListQuery> }) {
  const page = await getChatPage(await query);

  return <ChatTable items={page.items} nextCursor={page.nextCursor} />;
}

export function ChatListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
