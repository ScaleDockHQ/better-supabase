"use client";

import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useActionState, useId, useState } from "react";
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
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const result = await createCustomer(form);
      if (!result.ok) {
        return result.error.kind === "rate_limited"
          ? t(
              "Too many new customers. Try again in {seconds, number} seconds.",
              {
                seconds: result.error.retryAfter ?? 60,
              },
            )
          : errorMessage(result.error);
      }
      setOpen(false);
      toast.success(t("{name} added", { name: result.data.name }));
      return null;
    },
    null,
  );
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button />}>
        <PlusIcon />
        {t("Add customer")}
      </DialogTrigger>
      <DialogContent>
        <form action={submit} className="grid gap-6">
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
            <Button type="submit" disabled={pending}>
              {t("Add")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
