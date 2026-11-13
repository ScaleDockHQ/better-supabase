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
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";

import { respondToReview } from "../reviews-actions";

/** Rejects a review with a reason, or sets the organization's public reply. */
export function ReviewResponseDialog({
  reviewId,
  kind,
}: {
  reviewId: string;
  kind: "reject" | "reply";
}) {
  const t = useExtracted("reviews");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(respondToReview, {
    onSuccess: () => {
      toast.success(t("Review updated"));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);
  const rejecting = kind === "reject";

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        {rejecting ? t("Reject") : t("Reply")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="reviewId" value={reviewId} />
          <input type="hidden" name="kind" value={kind} />
          <DialogHeader>
            <DialogTitle>
              {rejecting ? t("Reject the review") : t("Reply to the review")}
            </DialogTitle>
            <DialogDescription>
              {rejecting
                ? t("The author sees the reason.")
                : t("The reply shows under the review on the store.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-text`}>
                {rejecting ? t("Reason") : t("Reply")}
              </FieldLabel>
              <Textarea
                id={`${fieldId}-text`}
                name="text"
                required
                maxLength={1000}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {rejecting ? t("Reject") : t("Send reply")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
