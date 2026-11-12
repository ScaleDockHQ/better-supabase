"use client";

import { useActionForm } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
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
import { useErrorMessage } from "@/lib/use-error-message";

import { requestSupportSession } from "../support-actions";

/** Asks for a read-only support session on one user. */
export function RequestSupportDialog() {
  const t = useExtracted("support");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(requestSupportSession, {
    onSuccess: () => {
      toast.success(t("Request sent for approval"));
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
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Request session")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Request session")}</DialogTitle>
            <DialogDescription>
              {t(
                "A second platform admin approves the request. The session is read-only, expires on its own and is recorded in the audit log.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-target`}>
                {t("User id")}
              </FieldLabel>
              <Input
                id={`${fieldId}-target`}
                name="target"
                required
                autoComplete="off"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-reason`}>
                {t("Reason")}
              </FieldLabel>
              <Textarea
                id={`${fieldId}-reason`}
                name="reason"
                required
                maxLength={500}
                rows={3}
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Send request")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
