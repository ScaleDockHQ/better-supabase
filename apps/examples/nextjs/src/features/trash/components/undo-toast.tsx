// #region recipe:undo-toast
"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { useErrorMessage } from "@/lib/use-error-message";

import { restoreTrashItem } from "../trash-actions";

export interface TrashedRecord {
  /** The trash item the delete returned. */
  readonly trashItemId: string;
  readonly name: string;
}

/**
 * Returns `show`, which confirms a delete with a toast whose Undo button
 * restores the record's whole trash batch.
 */
export function useUndoToast() {
  const t = useExtracted("trash");
  const errorMessage = useErrorMessage();

  const restore = useAction(restoreTrashItem, {
    onSuccess: () => {
      toast.success(t("Restored"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return function show({ trashItemId, name }: TrashedRecord) {
    toast(
      <span data-recipe="undo-toast">
        {t("{name} moved to the trash", { name })}
      </span>,
      {
        action: {
          label: t("Undo"),
          onClick: () => {
            void restore.run({ id: trashItemId });
          },
        },
      },
    );
  };
}
// #endregion recipe:undo-toast
