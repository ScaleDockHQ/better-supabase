"use client";

import { BellPlusIcon, CheckCheckIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { markAllRead, notifyMe } from "../inbox-actions";

export function InboxActions() {
  const t = useExtracted("inbox");
  const errorMessage = useErrorMessage();
  const [pending, start] = useTransition();
  return (
    <>
      <Button
        variant="outline"
        disabled={pending}
        onClick={() => {
          start(async () => {
            const result = await notifyMe({ title: t("Hello from the inbox") });
            if (result.ok) toast.success(t("Notification sent"));
            else toast.error(errorMessage(result.error));
          });
        }}
      >
        <BellPlusIcon />
        {t("Notify me")}
      </Button>
      <Button
        disabled={pending}
        onClick={() => {
          start(async () => {
            const result = await markAllRead({});
            if (result.ok) toast.success(t("All caught up"));
            else toast.error(errorMessage(result.error));
          });
        }}
      >
        <CheckCheckIcon />
        {t("Mark all read")}
      </Button>
    </>
  );
}
