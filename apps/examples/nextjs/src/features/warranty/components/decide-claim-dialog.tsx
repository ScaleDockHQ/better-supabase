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
import { inputFieldMessages } from "@/lib/input-field-messages";
import { toast } from "@/lib/toast";

import { decideClaim } from "../warranty-actions";

/** Approves or denies a submitted claim; the decision says why. */
export function DecideClaimDialog({
  claimId,
  status,
}: {
  claimId: string;
  status: "approved" | "denied";
}) {
  const t = useExtracted("warranty");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(decideClaim, {
    onSuccess: () => {
      toast.success(t("Claim updated"));
      setOpen(false);
    },
  });

  const fieldMessage = inputFieldMessages(form.error)["decision"];

  const error =
    form.error === undefined || fieldMessage !== undefined
      ? null
      : errorMessage(form.error);

  const approving = status === "approved";

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        form.reset();
      }}
    >
      <DialogTrigger
        render={
          <Button size="sm" variant={approving ? "default" : "outline"} />
        }
      >
        {approving ? t("Approve") : t("Deny")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="claimId" value={claimId} />
          <input type="hidden" name="status" value={status} />
          <DialogHeader>
            <DialogTitle>
              {approving ? t("Approve the claim") : t("Deny the claim")}
            </DialogTitle>
            <DialogDescription>
              {t(
                "The decision is stored with the claim and shown to the filer.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error || fieldMessage ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-decision`}>
                {t("Decision")}
              </FieldLabel>
              <Textarea
                id={`${fieldId}-decision`}
                name="decision"
                maxLength={1000}
                aria-invalid={fieldMessage ? true : undefined}
              />
              {fieldMessage ? <FieldError>{fieldMessage}</FieldError> : null}
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {approving ? t("Approve") : t("Deny")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
