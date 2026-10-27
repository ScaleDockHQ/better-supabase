"use client";

import { useAction } from "better-supabase/react";
import { ArchiveIcon, ArchiveRestoreIcon, Trash2Icon } from "lucide-react";
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
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import { deleteTeam, setTeamArchived } from "../teams-actions";

/** Archive or restore a team, and delete it after a confirmation. */
export function TeamStatusActions({
  id,
  name,
  archived,
}: {
  id: string;
  name: string;
  archived: boolean;
}) {
  const t = useExtracted("teams");
  const router = useRouter();
  const errorMessage = useErrorMessage();

  const setArchived = useAction(setTeamArchived, {
    onSuccess: () => {
      toast.success(archived ? t("Team restored") : t("Team archived"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const remove = useAction(deleteTeam, {
    onSuccess: () => {
      toast.success(t("Team deleted"));
      router.push("/settings/teams");
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <div className="flex items-center gap-2">
      <Button
        size="sm"
        variant="outline"
        disabled={setArchived.pending}
        onClick={() => {
          void setArchived.run({ id, archived: !archived });
        }}
      >
        {archived ? <ArchiveRestoreIcon /> : <ArchiveIcon />}
        {archived ? t("Restore") : t("Archive")}
      </Button>
      <AlertDialog>
        <AlertDialogTrigger render={<Button size="sm" variant="destructive" />}>
          <Trash2Icon />
          {t("Delete")}
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("Delete {name}?", { name })}</AlertDialogTitle>
            <AlertDialogDescription>
              {t(
                "Its members stay in the organization, and the customers it owned keep no owner.",
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={remove.pending}>
              {t("Cancel")}
            </AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              disabled={remove.pending}
              onClick={() => {
                void remove.run({ id });
              }}
            >
              {t("Delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
