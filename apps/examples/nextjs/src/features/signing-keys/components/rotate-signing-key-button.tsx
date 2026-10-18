"use client";

import { KeyRoundIcon, RefreshCwIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState, useTransition } from "react";
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

import { rotateSigningKey } from "../signing-keys-actions";

/**
 * Rotates behind a confirm. With no key yet (`first`), the same action
 * creates one, so the empty state uses it too.
 */
export function RotateSigningKeyButton({ first }: { first: boolean }) {
  const t = useExtracted("signingKeys");
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();

  return (
    <AlertDialog
      open={open}
      onOpenChange={(next) => {
        if (!pending) {
          setOpen(next);
        }
      }}
    >
      <AlertDialogTrigger
        render={<Button size="sm" variant={first ? "default" : "outline"} />}
      >
        {first ? <KeyRoundIcon /> : <RefreshCwIcon />}
        {first ? t("Create a signing key") : t("Rotate key")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            {first ? t("Create a signing key?") : t("Rotate the signing key?")}
          </AlertDialogTitle>
          <AlertDialogDescription>
            {first
              ? t(
                  "A new Ed25519 key is generated and stored in Vault. Its public half is published in the JWKS.",
                )
              : t(
                  "New tokens are signed with a new key. The current key stays published until the tokens it signed expire, so nothing breaks.",
                )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>
            {t("Cancel")}
          </AlertDialogCancel>
          <AlertDialogAction
            disabled={pending}
            onClick={(event) => {
              event.preventDefault();
              startTransition(async () => {
                const rotated = await rotateSigningKey({});

                if (!rotated.ok) {
                  toast.error(errorMessage(rotated.error));

                  return;
                }

                toast.success(
                  first ? t("Signing key created") : t("Signing key rotated"),
                );
                setOpen(false);
              });
            }}
          >
            {first ? t("Create key") : t("Rotate")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
