import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { loadChatBranch } from "@/features/assistant/assistant-search-params";
import {
  StoredChat,
  StoredChatSkeleton,
} from "@/features/assistant/components/stored-chat";
import { Link } from "@/i18n/navigation";

// The back link paints at once; the stored chat streams in.
export const instant = true;

/** The back link is the static shell; the stored chat streams in. */
export default function AssistantChatPage({
  params,
  searchParams,
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
        {Promise.all([params, loadChatBranch(searchParams)]).then(
          ([{ id }, { leaf }]) => (
            <StoredChat id={id} leaf={leaf ?? undefined} />
          ),
        )}
      </Suspense>
    </>
  );
}
