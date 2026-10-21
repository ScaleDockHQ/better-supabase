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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import { createDraftOrder } from "../shop-actions";

export interface OrderableProduct {
  readonly variantId: string;
  readonly label: string;
}

/**
 * Adds a catalog product to the caller's draft order, then opens it. The draft
 * is the caller's open cart, so a second add goes to the same draft.
 */
export function CreateDraftOrderDialog({
  products,
}: {
  products: readonly OrderableProduct[];
}) {
  const t = useExtracted("shop");
  const fieldId = useId();
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [variantId, setVariantId] = useState(products[0]?.variantId ?? "");

  const items = products.map((product) => ({
    value: product.variantId,
    label: product.label,
  }));

  const form = useActionForm(createDraftOrder, {
    onSuccess: (cartId) => {
      toast.success(t("Added to the draft order"));
      setOpen(false);
      router.push(`/shop/orders/${cartId}`);
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
      <DialogTrigger
        render={<Button size="sm" disabled={products.length === 0} />}
      >
        <PlusIcon />
        {t("New draft order")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New draft order")}</DialogTitle>
            <DialogDescription>
              {t(
                "Pick a product. It goes on your draft order, which you place from its page.",
              )}
            </DialogDescription>
          </DialogHeader>
          <input type="hidden" name="variantId" value={variantId} />
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-product`}>
                {t("Product")}
              </FieldLabel>
              <Select
                value={variantId}
                items={items}
                onValueChange={(value) => {
                  const picked = products.find(
                    (product) => product.variantId === value,
                  );

                  if (picked) {
                    setVariantId(picked.variantId);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-product`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {items.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-quantity`}>
                {t("Quantity")}
              </FieldLabel>
              <Input
                id={`${fieldId}-quantity`}
                name="quantity"
                type="number"
                min={1}
                max={999}
                step={1}
                defaultValue={1}
                required
                className="w-24"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending || !variantId}>
              {t("Add to draft")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
