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
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import { createQuote } from "../crm-actions";
import { FormSelect } from "./form-select";

/** Creates a draft quote, then opens the builder. */
export function CreateQuoteDialog({
  variant = "default",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("crm");
  const fieldId = useId();
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createQuote, {
    onSuccess: (quote) => {
      setOpen(false);
      toast.success(t("Quote created"));
      router.push(`/crm/quotes/${quote.id}`);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant={variant} />}>
        <PlusIcon />
        {t("New quote")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New quote")}</DialogTitle>
            <DialogDescription>
              {t("Add the line items on the next page.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Title")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                placeholder={t("Annual plan for Acme")}
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-currency`}>
                {t("Currency")}
              </FieldLabel>
              <FormSelect
                id={`${fieldId}-currency`}
                name="currency"
                defaultValue="EUR"
                items={[
                  { value: "EUR", label: "EUR" },
                  { value: "USD", label: "USD" },
                  { value: "GBP", label: "GBP" },
                ]}
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
