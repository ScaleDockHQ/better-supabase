"use client";

import { useErrorMessage } from "better-supabase/react";
import { KeyRoundIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useTransition } from "react";

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
import { toast } from "@/lib/toast";

import { rotateFieldKey } from "../encryption-actions";

/** Rotates the organization's data key after a confirm. */
export function RotateKeyButton() {
  const t = useExtracted("encryption");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  const rotate = () => {
    startTransition(async () => {
      const rotated = await rotateFieldKey({});

      if (!rotated.ok) {
        toast.error(errorMessage(rotated.error));

        return;
      }

      toast.success(
        t("Key rotated; {count} stored values encrypted again", {
          count: String(rotated.data),
        }),
      );
    });
  };

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={<Button size="sm" variant="outline" disabled={pending} />}
      >
        <KeyRoundIcon aria-hidden />
        {t("Rotate key")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("Rotate the data key?")}</AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "A new key replaces the current one and every encrypted value is encrypted again in one step. Writes to those tables wait until it finishes.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>
            {t("Cancel")}
          </AlertDialogCancel>
          <AlertDialogAction disabled={pending} onClick={rotate}>
            {t("Rotate key")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
