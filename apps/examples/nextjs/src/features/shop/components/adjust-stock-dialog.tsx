"use client";

import {
  type AdjustReason,
  ADJUST_REASONS,
} from "better-supabase/blocks/inventory";
import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";
import * as v from "valibot";

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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import { adjustStock } from "../shop-actions";

/** Adds or removes units of one variant at one location. */
export function AdjustStockDialog({
  variantId,
  locationId,
  label,
}: {
  variantId: string;
  locationId: string;
  label: string;
}) {
  const t = useExtracted("shop");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState<AdjustReason>("receipt");

  const reasonLabels: Record<AdjustReason, string> = {
    adjustment: t("Correction"),
    damage: t("Damaged"),
    loss: t("Lost"),
    return: t("Returned"),
    receipt: t("Received"),
  };

  const reasons = ADJUST_REASONS.map((value) => ({
    value,
    label: reasonLabels[value],
  }));

  const form = useActionForm(adjustStock, {
    onSuccess: (onHand) => {
      toast.success(t("{count, number} on hand now", { count: onHand }));
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
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        {t("Adjust")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Adjust stock")}</DialogTitle>
            <DialogDescription>{label}</DialogDescription>
          </DialogHeader>
          <input type="hidden" name="variantId" value={variantId} />
          <input type="hidden" name="locationId" value={locationId} />
          <input type="hidden" name="reason" value={reason} />
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-quantity`}>
                {t("Quantity")}
              </FieldLabel>
              <Input
                id={`${fieldId}-quantity`}
                name="quantity"
                type="number"
                step={1}
                required
                defaultValue={10}
              />
              <FieldDescription>
                {t("A negative number removes units.")}
              </FieldDescription>
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-reason`}>
                {t("Reason")}
              </FieldLabel>
              <Select
                value={reason}
                items={reasons}
                onValueChange={(value) => {
                  if (v.is(v.picklist(ADJUST_REASONS), value)) {
                    setReason(value);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-reason`} className="w-40">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {reasons.map((each) => (
                    <SelectItem key={each.value} value={each.value}>
                      {each.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-note`}>{t("Note")}</FieldLabel>
              <Input
                id={`${fieldId}-note`}
                name="note"
                maxLength={500}
                autoComplete="off"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
