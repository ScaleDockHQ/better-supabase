"use client";

import { useActionForm } from "better-supabase/react";
import { CopyPlusIcon } from "lucide-react";
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
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import { applyTemplate } from "../templates-actions";

/** Applies a template: creates a customer from it, then opens the customer. */
export function UseTemplateDialog({
  templateId,
  templateName,
  disabled,
}: {
  templateId: string;
  templateName: string;
  disabled: boolean;
}) {
  const t = useExtracted("templates");
  const fieldId = useId();
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(applyTemplate, {
    onSuccess: ({ customerId }) => {
      setOpen(false);
      toast.success(t("Customer created from {name}", { name: templateName }));
      router.push(`/customers/${customerId}`);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={<Button variant="outline" size="sm" disabled={disabled} />}
      >
        <CopyPlusIcon />
        {t("Use template")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="templateId" value={templateId} />
          <DialogHeader>
            <DialogTitle>
              {t("New customer from {name}", { name: templateName })}
            </DialogTitle>
            <DialogDescription>
              {t("The customer starts with the template's values.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>
                {t("Customer name")}
              </FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={200}
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create customer")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
