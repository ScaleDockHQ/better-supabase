"use client";

import type { DbError } from "better-supabase";

import { useAction } from "better-supabase/react";
import { RotateCcwIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { purgeTrashItem, restoreTrashItem } from "../trash-actions";

export function TrashItemActions({
  id,
  title,
  canPurge,
}: {
  id: string;
  title: string;
  canPurge: boolean;
}) {
  const t = useExtracted("trash");
  const errorMessage = useErrorMessage();

  const onError = (error: DbError) => {
    toast.error(errorMessage(error));
  };

  const restore = useAction(restoreTrashItem, {
    onSuccess: () => {
      toast.success(t("{title} restored", { title }));
    },
    onError,
  });

  const purge = useAction(purgeTrashItem, {
    onSuccess: () => {
      toast.success(t("{title} deleted for good", { title }));
    },
    onError,
  });

  const pending = restore.pending || purge.pending;

  return (
    <div className="flex justify-end gap-2">
      <Button
        size="sm"
        variant="outline"
        disabled={pending}
        onClick={() => {
          void restore.run({ id });
        }}
      >
        <RotateCcwIcon />
        {t("Restore")}
      </Button>
      {canPurge ? (
        <AlertDialog>
          <AlertDialogTrigger
            render={
              <Button size="sm" variant="destructive" disabled={pending} />
            }
          >
            <Trash2Icon />
            {t("Delete forever")}
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>
                {t("Delete {title} for good?", { title })}
              </AlertDialogTitle>
              <AlertDialogDescription>
                {t(
                  "It and everything trashed with it are removed. This can't be undone.",
                )}
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel disabled={purge.pending}>
                {t("Cancel")}
              </AlertDialogCancel>
              <AlertDialogAction
                variant="destructive"
                disabled={purge.pending}
                onClick={() => {
                  void purge.run({ id });
                }}
              >
                {t("Delete forever")}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      ) : null}
    </div>
  );
}
