"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { XIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { removeEventReminder } from "@/features/calendar/calendar-actions";
import { toast } from "@/lib/toast";

/** One reminder of the caller, with a button that removes it. */
export function MyReminderRow({
  id,
  subject,
  offsetMinutes,
  at,
}: {
  id: string;
  subject: string;
  offsetMinutes: number;
  /** The formatted time of a one-time reminder. */
  at: string | null;
}) {
  const t = useExtracted("myWork");
  const errorMessage = useErrorMessage();

  const remove = useAction(removeEventReminder, {
    onSuccess: () => {
      toast.success(t("Reminder removed"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const when =
    at ?? t("{count} minutes before", { count: String(offsetMinutes) });

  return (
    <li className="flex items-center justify-between gap-2 rounded-lg border p-3">
      <div className="flex min-w-0 flex-col gap-1">
        <span className="truncate text-sm font-medium">{subject}</span>
        <span className="text-xs text-muted-foreground">{when}</span>
      </div>
      <Button
        type="button"
        variant="ghost"
        size="icon-sm"
        aria-label={t("Remove the reminder on {subject}", { subject })}
        disabled={remove.pending}
        onClick={() => {
          void remove.run({ reminderId: id });
        }}
      >
        <XIcon />
      </Button>
    </li>
  );
}
