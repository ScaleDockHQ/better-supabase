"use client";

import { useExtracted } from "next-intl";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { dismissAnnouncement } from "../announcements-actions";

/** Hides one announcement for the caller. */
export function DismissButton({ id }: { id: string }) {
  const t = useExtracted("announcements");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const result = await dismissAnnouncement({ id });

          if (result.ok) {
            toast.success(t("Announcement dismissed"));
          } else {
            toast.error(errorMessage(result.error));
          }
        });
      }}
    >
      {t("Dismiss")}
    </Button>
  );
}
