"use client";

import { useAction } from "better-supabase/react";
import { ArchiveIcon, PinIcon, PinOffIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { updateChat } from "../assistant-actions";

/** The chat's title with pin and archive. */
export function ChatActions({
  chatId,
  title,
  pinned,
}: {
  chatId: string;
  title: string;
  pinned: boolean;
}) {
  const t = useExtracted("assistant");
  const router = useRouter();
  const errorMessage = useErrorMessage();

  const save = useAction(updateChat, {
    onSuccess: (_id, input) => {
      if (input.archived === true) {
        router.push("/assistant");
      }
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <div className="flex flex-wrap items-center justify-between gap-2">
      <h1 className="truncate text-xl font-semibold tracking-tight">
        {title === "" ? t("Untitled chat") : title}
      </h1>
      <div className="flex items-center gap-2">
        <Button
          size="sm"
          variant="outline"
          disabled={save.pending}
          onClick={() => {
            void save.run({ chatId, pinned: !pinned });
          }}
        >
          {pinned ? <PinOffIcon /> : <PinIcon />}
          {pinned ? t("Unpin") : t("Pin")}
        </Button>
        <Button
          size="sm"
          variant="outline"
          disabled={save.pending}
          onClick={() => {
            void save.run({ chatId, archived: true });
          }}
        >
          <ArchiveIcon />
          {t("Archive")}
        </Button>
      </div>
    </div>
  );
}
