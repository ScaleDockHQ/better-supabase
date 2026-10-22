"use client";

import { useAction } from "better-supabase/react";
import { ClockIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
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
import { useErrorMessage } from "@/lib/use-error-message";

import { setWorkingHours } from "../calendar-actions";

/** Sets the caller's working hours, Monday to Friday, in their browser's zone. */
export function WorkingHoursDialog() {
  const t = useExtracted("calendar");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const save = useAction(setWorkingHours, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Working hours saved"));
    },
  });

  const error = save.error === undefined ? null : errorMessage(save.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        <ClockIcon />
        {t("Working hours")}
      </DialogTrigger>
      <DialogContent>
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault();
            const data = new FormData(event.currentTarget);
            void save.run({
              tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
              start: String(data.get("start")),
              end: String(data.get("end")),
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>{t("Working hours")}</DialogTitle>
            <DialogDescription>
              {t(
                "Monday to Friday, in your time zone. Free/busy and find-a-time use them.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
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
                  defaultValue="17:00"
                />
              </Field>
            </div>
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={save.pending}>
              {t("Save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
