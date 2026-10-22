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

import { createShipment } from "../field-actions";

/** A dialog that creates a draft shipment of one package. */
export function NewShipmentDialog() {
  const t = useExtracted("field");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createShipment, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Shipment created"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant="outline" />}>
        <PlusIcon />
        {t("New shipment")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New shipment")}</DialogTitle>
            <DialogDescription>
              {t("One package from the warehouse, saved as a draft.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={form.fieldErrors["name"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>
                {t("Recipient")}
              </FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={200}
                aria-invalid={form.fieldErrors["name"] ? true : undefined}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-line1`}>
                {t("Street and number")}
              </FieldLabel>
              <Input
                id={`${fieldId}-line1`}
                name="line1"
                required
                maxLength={200}
              />
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel htmlFor={`${fieldId}-postal`}>
                  {t("Postal code")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-postal`}
                  name="postalCode"
                  maxLength={20}
                />
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-city`}>{t("City")}</FieldLabel>
                <Input
                  id={`${fieldId}-city`}
                  name="city"
                  required
                  maxLength={100}
                />
              </Field>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <Field
                data-invalid={form.fieldErrors["country"] ? true : undefined}
              >
                <FieldLabel htmlFor={`${fieldId}-country`}>
                  {t("Country code")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-country`}
                  name="country"
                  required
                  minLength={2}
                  maxLength={2}
                  placeholder="NL"
                  aria-invalid={form.fieldErrors["country"] ? true : undefined}
                />
              </Field>
              <Field
                data-invalid={
                  form.fieldErrors["weightGrams"] ? true : undefined
                }
              >
                <FieldLabel htmlFor={`${fieldId}-weight`}>
                  {t("Weight in grams")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-weight`}
                  name="weightGrams"
                  type="number"
                  min={1}
                  max={70_000}
                  defaultValue={1000}
                  required
                  aria-invalid={
                    form.fieldErrors["weightGrams"] ? true : undefined
                  }
                />
              </Field>
            </div>
            {error ? <FieldError>{error}</FieldError> : null}
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
