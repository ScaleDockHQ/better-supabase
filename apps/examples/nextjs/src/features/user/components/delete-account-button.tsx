"use client";

import { useSessionChange } from "better-supabase/next/client";
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
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useRouter } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";
import { useErrorMessage } from "@/lib/use-error-message";

import { deleteMyAccount, sessionChanged } from "../user-actions";

export function DeleteAccountCard() {
  const t = useExtracted("security");
  const errorMessage = useErrorMessage();
  const supabase = useSupabase();
  const router = useRouter();
  const changeSession = useSessionChange(sessionChanged, router);
  const [pending, startTransition] = useTransition();
  return (
    <Card className="ring-destructive/30">
      <CardHeader>
        <CardTitle>{t("Delete account")}</CardTitle>
        <CardDescription>
          {t(
            "Removes your user and your notifications. Organizations you own stay.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <AlertDialog>
          <AlertDialogTrigger render={<Button variant="destructive" />}>
            {t("Delete account")}
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>{t("Delete your account?")}</AlertDialogTitle>
              <AlertDialogDescription>
                {t(
                  "This can't be undone. You need a verified second factor in this session.",
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
                    const result = await deleteMyAccount(undefined);
                    if (!result.ok) {
                      toast.error(
                        result.error.kind === "forbidden"
                          ? t("Verify a second factor first, then try again.")
                          : errorMessage(result.error),
                      );
                      return;
                    }
                    // The user is gone: drop the session without calling Auth.
                    await supabase.auth.signOut({ scope: "local" });
                    await changeSession("/login");
                  });
                }}
              >
                {t("Delete")}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </CardContent>
    </Card>
  );
}
