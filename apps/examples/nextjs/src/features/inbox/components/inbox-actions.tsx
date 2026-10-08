"use client";

import { useAction } from "better-supabase/react";
import { BellPlusIcon, CheckCheckIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { markAllRead, notifyMe } from "../inbox-actions";

export function InboxActions() {
  const t = useExtracted("inbox");
  const errorMessage = useErrorMessage();
  const notify = useAction(notifyMe, {
    onSuccess: () => {
      toast.success(t("Notification sent"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  const readAll = useAction(markAllRead, {
    onSuccess: () => {
      toast.success(t("All caught up"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  return (
    <>
      <Button
        variant="outline"
        disabled={notify.pending}
        onClick={() => {
          void notify.run({ title: t("Hello from the inbox") });
        }}
      >
        <BellPlusIcon />
        {t("Notify me")}
      </Button>
      <Button
        disabled={readAll.pending}
        onClick={() => {
          void readAll.run({});
        }}
      >
        <CheckCheckIcon />
        {t("Mark all read")}
      </Button>
    </>
  );
}
