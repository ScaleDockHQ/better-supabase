"use client";

import { useExtracted } from "next-intl";
import { useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import { acceptInvitation, declineInvitation } from "../organization-actions";
import { useRefreshSession } from "../use-refresh-session";

export function InvitationResponse({ token }: { token: string }) {
  const t = useExtracted("invitation");
  const errorMessage = useErrorMessage();
  const refreshSession = useRefreshSession();
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  return (
    <div className="flex w-full gap-2">
      <Button
        variant="outline"
        className="flex-1"
        disabled={pending}
        onClick={() => {
          startTransition(async () => {
            const result = await declineInvitation({ token });
            if (!result.ok) {
              toast.error(errorMessage(result.error));
              return;
            }
            router.push("/");
          });
        }}
      >
        {t("Decline")}
      </Button>
      <Button
        className="flex-1"
        disabled={pending}
        onClick={() => {
          startTransition(async () => {
            const result = await acceptInvitation({ token });
            if (!result.ok) {
              toast.error(errorMessage(result.error));
              return;
            }
            await refreshSession("/");
            toast.success(t("Welcome aboard"));
          });
        }}
      >
        {t("Accept invitation")}
      </Button>
    </div>
  );
}
