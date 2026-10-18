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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { createProduct } from "../shop-actions";
import { SHOP_CURRENCY } from "../shop-currency";

/** Creates an active product with one variant and its price. */
export function CreateProductDialog({
  variant = "default",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("shop");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createProduct, {
    onSuccess: () => {
      toast.success(t("Product created"));
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
        {t("New product")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New product")}</DialogTitle>
            <DialogDescription>
              {t("It goes on sale right away with one variant and its price.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                autoComplete="off"
                placeholder={t("Linen shirt")}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-sku`}>{t("SKU")}</FieldLabel>
              <Input
                id={`${fieldId}-sku`}
                name="sku"
                required
                maxLength={64}
                autoComplete="off"
                placeholder="LINEN-SHIRT"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-price`}>
                {t("Price ({currency})", { currency: SHOP_CURRENCY })}
              </FieldLabel>
              <Input
                id={`${fieldId}-price`}
                name="price"
                required
                inputMode="decimal"
                pattern="\d+(\.\d{1,2})?"
                placeholder="49.00"
              />
              <FieldDescription>
                {t("Stored in minor units, so 49.00 becomes 4900 cents.")}
              </FieldDescription>
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create product")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
