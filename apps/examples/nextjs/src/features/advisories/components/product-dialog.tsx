"use client";

import { useActionForm } from "better-supabase/react";
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
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { saveProduct } from "../advisories-actions";

/** Adds a product advisories are published for. */
export function ProductDialog() {
  const t = useExtracted("advisories");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(saveProduct, {
    onSuccess: () => {
      toast.success(t("Product saved"));
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
        <PlusIcon />
        {t("Add product")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add product")}</DialogTitle>
            <DialogDescription>
              {t("Advisories and VEX statements are written per product.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={120}
                autoComplete="off"
              />
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-key`}>{t("Key")}</FieldLabel>
              <Input
                id={`${fieldId}-key`}
                name="key"
                required
                pattern="[a-z0-9][a-z0-9_\-]*"
                autoComplete="off"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-vendor`}>
                {t("Vendor")}
              </FieldLabel>
              <Input
                id={`${fieldId}-vendor`}
                name="vendor"
                maxLength={120}
                autoComplete="off"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Save product")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
