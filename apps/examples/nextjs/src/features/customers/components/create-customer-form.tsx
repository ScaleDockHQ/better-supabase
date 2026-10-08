"use client";

import { useActionForm } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
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

import { createCustomer } from "../customer-actions";

export function CreateCustomerDialog() {
  const t = useExtracted("customers");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const form = useActionForm(createCustomer, {
    onSuccess: (customer) => {
      setOpen(false);
      toast.success(t("{name} added", { name: customer.name }));
    },
  });
  const error =
    form.error === undefined
      ? null
      : form.error.kind === "rate_limited"
        ? t("Too many new customers. Try again in {seconds, number} seconds.", {
            seconds: form.error.retryAfter ?? 60,
          })
        : errorMessage(form.error);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button />}>
        <PlusIcon />
        {t("Add customer")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add customer")}</DialogTitle>
            <DialogDescription>
              {t(
                "New customers start as leads and count toward your plan's quota.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-customer-name`}>
                {t("Name")}
              </FieldLabel>
              <Input
                id={`${fieldId}-customer-name`}
                name="name"
                placeholder={t("New customer")}
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
              {t("Add")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
