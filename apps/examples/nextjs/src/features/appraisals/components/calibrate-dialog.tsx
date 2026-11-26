"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

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
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";

import { calibrateAppraisal } from "../appraisals-actions";

/** Sets the calibrated rating of a reviewed appraisal, with the reason. */
export function CalibrateDialog({ appraisalId }: { appraisalId: string }) {
  const t = useExtracted("appraisals");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(calibrateAppraisal, {
    onSuccess: () => {
      toast.success(t("Appraisal calibrated"));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        {t("Calibrate")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="appraisalId" value={appraisalId} />
          <DialogHeader>
            <DialogTitle>{t("Calibrate")}</DialogTitle>
            <DialogDescription>
              {t(
                "The calibrated rating replaces the review average; the reason stays with it.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-rating`}>
                {t("Rating")}
              </FieldLabel>
              <Input
                id={`${fieldId}-rating`}
                name="rating"
                type="number"
                inputMode="numeric"
                min={1}
                max={5}
                step={1}
                required
              />
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-reason`}>
                {t("Reason")}
              </FieldLabel>
              <Textarea
                id={`${fieldId}-reason`}
                name="reason"
                required
                maxLength={2000}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Calibrate")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
