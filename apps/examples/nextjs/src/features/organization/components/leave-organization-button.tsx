"use client";

import { useExtracted } from "next-intl";
import { useTransition } from "react";
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

import { leaveOrganization } from "../organization-actions";
import { useRefreshSession } from "../use-refresh-session";

export function LeaveOrganizationButton({ name }: { name: string }) {
  const t = useExtracted("organization");
  const errorMessage = useErrorMessage();
  const refreshSession = useRefreshSession();
  const [pending, startTransition] = useTransition();
  return (
    <AlertDialog>
      <AlertDialogTrigger render={<Button variant="outline" />}>
        {t("Leave organization")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("Leave {name}?", { name })}</AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "You lose access to its customers until someone invites you again.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={pending}
            onClick={() => {
              startTransition(async () => {
                const result = await leaveOrganization({});
                if (!result.ok) {
                  toast.error(errorMessage(result.error));
                  return;
                }
                await refreshSession("/");
              });
            }}
          >
            {t("Leave")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
