"use client";

import { useAction } from "better-supabase/react";
import { BellPlusIcon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import { addEventReminder, removeEventReminder } from "../calendar-actions";
import { REMINDER_OFFSETS, type ReminderOffset } from "../calendar-subjects";

const isOffset = (value: unknown): value is ReminderOffset =>
  REMINDER_OFFSETS.some((offset) => offset === value);

function useOffsetLabel() {
  const t = useExtracted("calendar");

  return (minutes: number): string => {
    switch (minutes) {
      case 0: {
        return t("When it starts");
      }

      case 15: {
        return t("15 minutes before");
      }

      case 60: {
        return t("1 hour before");
      }

      case 1440: {
        return t("1 day before");
      }

      default: {
        return t("{count} minutes before", { count: String(minutes) });
      }
    }
  };
}

/** One upcoming event: its reminders as badges, and a picker to add one. */
export function EventReminders({
  eventId,
  title,
  when,
  reminders,
}: {
  eventId: string;
  title: string;
  when: string;
  reminders: readonly { id: string; offsetMinutes: number }[];
}) {
  const t = useExtracted("calendar");
  const selectId = useId();
  const offsetLabel = useOffsetLabel();
  const errorMessage = useErrorMessage();
  const [offset, setOffset] = useState<ReminderOffset>(60);

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const add = useAction(addEventReminder, {
    onSuccess: () => {
      toast.success(t("Reminder set"));
    },
    onError,
  });

  const remove = useAction(removeEventReminder, { onError });

  const taken = new Set(reminders.map((reminder) => reminder.offsetMinutes));

  const offsets = REMINDER_OFFSETS.filter((each) => !taken.has(each)).map(
    (each) => ({ value: each, label: offsetLabel(each) }),
  );

  const selected = taken.has(offset) ? offsets[0]?.value : offset;

  return (
    <li className="flex flex-col gap-2 rounded-lg border p-3">
      <div className="flex min-w-0 flex-col gap-1">
        <span className="truncate text-sm font-medium">{title}</span>
        <span className="text-xs text-muted-foreground">{when}</span>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {reminders.map((reminder) => (
          <Badge key={reminder.id} variant="info-light">
            {offsetLabel(reminder.offsetMinutes)}
            <button
              type="button"
              aria-label={t("Remove the reminder {when}", {
                when: offsetLabel(reminder.offsetMinutes),
              })}
              disabled={remove.pending}
              className="rounded-sm transition-colors hover:text-foreground"
              onClick={() => {
                void remove.run({ reminderId: reminder.id });
              }}
            >
              <XIcon aria-hidden="true" className="size-3" />
            </button>
          </Badge>
        ))}
        {selected === undefined ? null : (
          <form
            className="ms-auto flex items-center gap-2"
            onSubmit={(event) => {
              event.preventDefault();
              void add.run({ eventId, offsetMinutes: selected });
            }}
          >
            <label htmlFor={selectId} className="sr-only">
              {t("Remind me")}
            </label>
            <Select
              value={selected}
              items={offsets}
              onValueChange={(value) => {
                if (isOffset(value)) {
                  setOffset(value);
                }
              }}
            >
              <SelectTrigger id={selectId} size="sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {offsets.map((each) => (
                  <SelectItem key={each.value} value={each.value}>
                    {each.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button
              type="submit"
              variant="outline"
              size="sm"
              disabled={add.pending}
            >
              <BellPlusIcon />
              {t("Add")}
            </Button>
          </form>
        )}
      </div>
    </li>
  );
}
