import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  StoredChat,
  StoredChatSkeleton,
} from "@/features/assistant/components/stored-chat";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the stored chat streams in. */
export default function AssistantChatPage({
  params,
}: PageProps<"/[locale]/assistant/[id]">) {
  const t = useExtracted("assistant");
  return (
    <>
      <Link
        href="/assistant"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All chats")}
      </Link>
      <Suspense fallback={<StoredChatSkeleton />}>
        <StoredChat params={params} />
      </Suspense>
    </>
  );
}
