"use client";

import { useActionForm } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";
import { Temporal } from "temporal-polyfill";

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
import { useErrorMessage } from "@/lib/use-error-message";

import { logTime } from "../people-actions";

/** A dialog that logs a block of time on one day of `week` (its Monday). */
export function LogTimeDialog({ week }: { week: string }) {
  const t = useExtracted("people");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const sunday = Temporal.PlainDate.from(week).add({ days: 6 }).toString();

  const form = useActionForm(logTime, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Time logged"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant="outline" />}>
        <PlusIcon />
        {t("Log time")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Log time")}</DialogTitle>
            <DialogDescription>
              {t("Add a block of time you worked on a project this week.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field
              data-invalid={form.fieldErrors["project"] ? true : undefined}
            >
              <FieldLabel htmlFor={`${fieldId}-project`}>
                {t("Project")}
              </FieldLabel>
              <Input
                id={`${fieldId}-project`}
                name="project"
                required
                maxLength={200}
                aria-invalid={form.fieldErrors["project"] ? true : undefined}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-date`}>{t("Day")}</FieldLabel>
              <Input
                id={`${fieldId}-date`}
                name="date"
                type="date"
                min={week}
                max={sunday}
                defaultValue={week}
                required
              />
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel htmlFor={`${fieldId}-start`}>
                  {t("From")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-start`}
                  name="start"
                  type="time"
                  defaultValue="09:00"
                  required
                />
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-end`}>{t("To")}</FieldLabel>
                <Input
                  id={`${fieldId}-end`}
                  name="end"
                  type="time"
                  defaultValue="10:00"
                  required
                />
              </Field>
            </div>
            <Field orientation="horizontal">
              <Checkbox id={`${fieldId}-billable`} name="billable" value="on" />
              <FieldLabel htmlFor={`${fieldId}-billable`}>
                {t("Billable")}
              </FieldLabel>
            </Field>
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Log")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
