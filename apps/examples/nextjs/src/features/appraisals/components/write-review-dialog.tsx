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

import { submitAppraisalReview } from "../appraisals-actions";

/**
 * Writes the caller's review: one rating from 1 to 5 per competency of the
 * rubric, or one overall rating when the cycle has none.
 */
export function WriteReviewDialog({
  reviewId,
  rubric,
}: {
  reviewId: string;
  rubric: readonly { readonly key: string; readonly name: string }[];
}) {
  const t = useExtracted("appraisals");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(submitAppraisalReview, {
    onSuccess: () => {
      toast.success(t("Review submitted"));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  const scales =
    rubric.length === 0 ? [{ key: null, name: t("Rating") }] : rubric;

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        {t("Write review")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="reviewId" value={reviewId} />
          <DialogHeader>
            <DialogTitle>{t("Write review")}</DialogTitle>
            <DialogDescription>
              {t("Rate each competency from 1 to 5.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            {scales.map((scale) => (
              <Field key={scale.key ?? "overall"}>
                {scale.key === null ? null : (
                  <input type="hidden" name="competency" value={scale.key} />
                )}
                <FieldLabel htmlFor={`${fieldId}-${scale.key ?? "overall"}`}>
                  {scale.name}
                </FieldLabel>
                <Input
                  id={`${fieldId}-${scale.key ?? "overall"}`}
                  name="rating"
                  type="number"
                  inputMode="numeric"
                  min={1}
                  max={5}
                  step={1}
                  required
                />
              </Field>
            ))}
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-comments`}>
                {t("Comments")}
              </FieldLabel>
              <Textarea
                id={`${fieldId}-comments`}
                name="comments"
                maxLength={4000}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Submit review")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
