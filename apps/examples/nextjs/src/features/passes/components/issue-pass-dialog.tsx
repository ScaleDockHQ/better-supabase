"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/lib/toast";

import { issuePass } from "../passes-actions";

/** Issues a pass to a named holder. */
export function IssuePassDialog() {
  const t = useExtracted("passes");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(issuePass, {
    onSuccess: () => {
      toast.success(t("Pass issued"));
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
        {t("Issue a pass")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Issue a pass")}</DialogTitle>
            <DialogDescription>
              {t(
                "The holder gets a signed QR token that staff scan at the door.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>
                {t("Holder name")}
              </FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="holderName"
                required
                maxLength={120}
                autoComplete="off"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-email`}>{t("Email")}</FieldLabel>
              <Input
                id={`${fieldId}-email`}
                name="holderEmail"
                type="email"
                maxLength={200}
                autoComplete="off"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-uses`}>{t("Uses")}</FieldLabel>
              <Input
                id={`${fieldId}-uses`}
                name="usesAllowed"
                type="number"
                min={1}
                max={1000}
              />
              <FieldDescription>
                {t("Leave empty for unlimited entries.")}
              </FieldDescription>
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Issue pass")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
