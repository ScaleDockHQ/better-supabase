import { MessageSquareIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import { getChats } from "../assistant-queries";

/** Render inside `<Suspense>`. */
export async function ChatList() {
  const [chats, t, format] = await Promise.all([
    getChats(),
    getExtracted("assistant"),
    getFormatter(),
  ]);
  if (chats.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <MessageSquareIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No chats yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Your chats show up here after the first answer.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }
  return (
    <ul className="divide-y rounded-xl border">
      {chats.map((chat) => (
        <li key={chat.id}>
          <Link
            href={`/assistant/${chat.id}`}
            className="hover:bg-muted flex items-center gap-3 px-4 py-3 text-sm"
          >
            <span className="flex-1 truncate">
              {chat.title === "" ? t("Untitled chat") : chat.title}
            </span>
            <span className="text-muted-foreground text-xs tabular-nums">
              {format.dateTime(new Date(chat.lastMessageAt), {
                dateStyle: "medium",
                timeStyle: "short",
              })}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export function ChatListSkeleton() {
  return <Skeleton className="h-32 w-full rounded-xl" />;
}
