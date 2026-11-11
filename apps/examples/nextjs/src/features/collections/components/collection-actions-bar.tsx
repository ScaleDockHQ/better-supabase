"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { archiveCollection } from "../collections-actions";

/** Archives a collection, or brings an archived one back. */
export function CollectionActionsBar({
  collectionId,
  archived,
}: {
  collectionId: string;
  archived: boolean;
}) {
  const t = useExtracted("collections");
  const errorMessage = useErrorMessage();

  const archive = useAction(archiveCollection, {
    onSuccess: () => {
      toast.success(t("Collection updated"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={archive.pending}
      onClick={() => {
        void archive.run({ collectionId, archived: !archived });
      }}
    >
      {archived ? t("Restore") : t("Archive")}
    </Button>
  );
}
