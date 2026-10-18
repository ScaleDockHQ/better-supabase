"use client";

import { useAction } from "better-supabase/react";
import { useExtracted, useFormatter } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { FieldError } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useErrorMessage } from "@/lib/use-error-message";

import type { DayHours } from "../bookings-queries";

import { saveWeeklyHours } from "../bookings-actions";

interface DayDraft {
  readonly weekday: DayHours["weekday"];
  readonly open: boolean;
  readonly start: string;
  readonly end: string;
}

/** 2024-01-01 is a Monday, so day `n` of that week names weekday `n`. */
const weekdayDate = (weekday: number) =>
  new Date(Date.UTC(2024, 0, weekday, 12));

export function WeeklyHoursForm({ hours }: { hours: readonly DayHours[] }) {
  const t = useExtracted("bookings");
  const format = useFormatter();
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const [days, setDays] = useState<readonly DayDraft[]>(() =>
    hours.map((day) => ({
      weekday: day.weekday,
      open: day.start !== null,
      start: day.start ?? "09:00",
      end: day.end ?? "17:00",
    })),
  );

  const save = useAction(saveWeeklyHours, {
    onSuccess: () => {
      toast.success(t("Hours saved"));
    },
  });

  const invalid = days.some((day) => day.open && day.start >= day.end);

  const change = (weekday: number, patch: Partial<DayDraft>) => {
    setDays((current) =>
      current.map((day) =>
        day.weekday === weekday ? { ...day, ...patch } : day,
      ),
    );
  };

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        void save.run({
          hours: days
            .filter((day) => day.open)
            .map(({ weekday, start, end }) => ({ weekday, start, end })),
        });
      }}
    >
      <ul className="flex flex-col divide-y">
        {days.map((day) => {
          const id = `${fieldId}-${day.weekday}`;

          const name = format.dateTime(weekdayDate(day.weekday), {
            weekday: "long",
            timeZone: "UTC",
          });

          return (
            <li
              key={day.weekday}
              className="flex flex-wrap items-center gap-3 py-2"
            >
              <div className="flex w-36 items-center gap-2">
                <Checkbox
                  id={id}
                  checked={day.open}
                  onCheckedChange={(checked) => {
                    change(day.weekday, { open: checked });
                  }}
                />
                <Label htmlFor={id}>{name}</Label>
              </div>
              {day.open ? (
                <div className="flex items-center gap-2">
                  <Input
                    type="time"
                    aria-label={t("{day} from", { day: name })}
                    value={day.start}
                    onChange={(event) => {
                      change(day.weekday, { start: event.target.value });
                    }}
                    className="w-32"
                  />
                  <span className="text-sm text-muted-foreground">
                    {t("to")}
                  </span>
                  <Input
                    type="time"
                    aria-label={t("{day} until", { day: name })}
                    aria-invalid={day.start >= day.end ? true : undefined}
                    value={day.end}
                    onChange={(event) => {
                      change(day.weekday, { end: event.target.value });
                    }}
                    className="w-32"
                  />
                </div>
              ) : (
                <span className="text-sm text-muted-foreground">
                  {t("Unavailable")}
                </span>
              )}
            </li>
          );
        })}
      </ul>
      {invalid ? (
        <FieldError>{t("Each day has to end after it starts.")}</FieldError>
      ) : null}
      {save.error ? <FieldError>{errorMessage(save.error)}</FieldError> : null}
      <div className="flex justify-end gap-2">
        <Button type="submit" disabled={save.pending || invalid}>
          {t("Save hours")}
        </Button>
      </div>
    </form>
  );
}
