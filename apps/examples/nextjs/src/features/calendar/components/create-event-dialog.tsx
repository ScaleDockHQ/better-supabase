"use client";

import { useActionForm } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import type { CalendarSummary } from "../calendar-queries";

import { createEvent } from "../calendar-actions";

export function CreateEventDialog({
  calendars,
  defaultDate,
}: {
  calendars: readonly CalendarSummary[];
  defaultDate: string;
}) {
  const t = useExtracted("calendar");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [calendarId, setCalendarId] = useState(calendars[0]?.id ?? "");
  const [allDay, setAllDay] = useState(false);

  const tz =
    calendars.find((calendar) => calendar.id === calendarId)?.tz ?? "UTC";

  const form = useActionForm(createEvent, {
    resetOnSuccess: true,
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Event added"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  const items = calendars.map((calendar) => ({
    value: calendar.id,
    label: calendar.name,
  }));

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("New event")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="tz" value={tz} />
          <DialogHeader>
            <DialogTitle>{t("New event")}</DialogTitle>
            <DialogDescription>
              {t("Times are in the calendar's zone, {tz}.", { tz })}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={form.fieldErrors["title"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Title")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                aria-invalid={form.fieldErrors["title"] ? true : undefined}
              />
            </Field>
            {calendars.length > 1 ? (
              <Field>
                <FieldLabel htmlFor={`${fieldId}-calendar`}>
                  {t("Calendar")}
                </FieldLabel>
                <Select
                  name="calendarId"
                  items={items}
                  value={calendarId}
                  onValueChange={(value) => {
                    setCalendarId(value ?? "");
                  }}
                >
                  <SelectTrigger id={`${fieldId}-calendar`} className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {items.map((item) => (
                      <SelectItem key={item.value} value={item.value}>
                        {item.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
            ) : (
              <input type="hidden" name="calendarId" value={calendarId} />
            )}
            <Field data-invalid={form.fieldErrors["date"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-date`}>{t("Day")}</FieldLabel>
              <Input
                id={`${fieldId}-date`}
                name="date"
                type="date"
                required
                defaultValue={defaultDate}
              />
            </Field>
            <Field orientation="horizontal">
              <Checkbox
                id={`${fieldId}-all-day`}
                name="allDay"
                value="on"
                checked={allDay}
                onCheckedChange={(checked) => {
                  setAllDay(checked);
                }}
              />
              <FieldLabel htmlFor={`${fieldId}-all-day`}>
                {t("All day")}
              </FieldLabel>
            </Field>
            {allDay ? null : (
              <div className="grid grid-cols-2 gap-4">
                <Field>
                  <FieldLabel htmlFor={`${fieldId}-start`}>
                    {t("From")}
                  </FieldLabel>
                  <Input
                    id={`${fieldId}-start`}
                    name="start"
                    type="time"
                    required
                    defaultValue="09:00"
                  />
                </Field>
                <Field>
                  <FieldLabel htmlFor={`${fieldId}-end`}>{t("To")}</FieldLabel>
                  <Input
                    id={`${fieldId}-end`}
                    name="end"
                    type="time"
                    required
                    defaultValue="10:00"
                  />
                </Field>
              </div>
            )}
            <Field>
              <FieldLabel htmlFor={`${fieldId}-location`}>
                {t("Location")}
              </FieldLabel>
              <Input
                id={`${fieldId}-location`}
                name="location"
                maxLength={200}
              />
            </Field>
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Add event")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
