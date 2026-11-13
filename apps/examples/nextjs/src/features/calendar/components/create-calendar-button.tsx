"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { createCalendar } from "../calendar-actions";

/** Creates the team calendar in the zone of the browser that clicks it. */
export function CreateCalendarButton() {
  const t = useExtracted("calendar");
  const errorMessage = useErrorMessage();

  const create = useAction(createCalendar, {
    onSuccess: () => {
      toast.success(t("Calendar created"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      disabled={create.pending}
      onClick={() =>
        void create.run({
          name: t("Team"),
          tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        })
      }
    >
      <PlusIcon />
      {t("Create calendar")}
    </Button>
  );
}
