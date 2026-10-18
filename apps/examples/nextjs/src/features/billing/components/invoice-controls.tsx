"use client";

import { useAction, useActionForm } from "better-supabase/react";
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
import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { useErrorMessage } from "@/lib/use-error-message";

import { createDraftInvoice, issueInvoice } from "../invoice-actions";

/** Creates a draft invoice with one line. */
export function CreateDraftInvoiceDialog({
  variant = "default",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("billing");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createDraftInvoice, {
    onSuccess: () => {
      toast.success(t("Draft invoice created"));
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
      <DialogTrigger render={<Button size="sm" variant={variant} />}>
        <PlusIcon />
        {t("New draft invoice")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New draft invoice")}</DialogTitle>
            <DialogDescription>
              {t("A draft has no number yet. Issue it to send it.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>
                {t("Description")}
              </FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                autoComplete="off"
                placeholder={t("October support")}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-amount`}>
                {t("Amount ({currency})", { currency: SHOP_CURRENCY })}
              </FieldLabel>
              <Input
                id={`${fieldId}-amount`}
                name="amount"
                required
                inputMode="decimal"
                pattern="\d+(\.\d{1,2})?"
                placeholder="190.00"
                className="w-32"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create draft")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function IssueInvoiceButton({ invoiceId }: { invoiceId: string }) {
  const t = useExtracted("billing");
  const errorMessage = useErrorMessage();

  const issue = useAction(issueInvoice, {
    onSuccess: () => {
      toast.success(t("Invoice issued"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={issue.pending}
      onClick={() => {
        void issue.run({ invoiceId });
      }}
    >
      {t("Issue")}
    </Button>
  );
}
