"use client";

import { useExtracted } from "next-intl";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { liftBan } from "../moderation-actions";

export function LiftBanButton({ banId }: { banId: string }) {
  const t = useExtracted("moderation");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const result = await liftBan({ banId });

          if (result.ok) {
            toast.success(t("Ban lifted"));
          } else {
            toast.error(errorMessage(result.error));
          }
        });
      }}
    >
      {t("Lift ban")}
    </Button>
  );
}
