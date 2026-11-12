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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { createAsset } from "../assets-actions";

/** Adds an asset to the register. */
export function CreateAssetDialog() {
  const t = useExtracted("assets");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createAsset, {
    onSuccess: () => {
      toast.success(t("Asset added"));
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
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("New asset")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New asset")}</DialogTitle>
            <DialogDescription>
              {t("Add equipment, a vehicle or a unit to the register.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={200}
                autoComplete="off"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-kind`}>{t("Kind")}</FieldLabel>
              <Input
                id={`${fieldId}-kind`}
                name="kind"
                required
                maxLength={60}
                autoComplete="off"
                pattern="[a-z][a-z0-9_]{0,62}"
                placeholder="vehicle"
              />
              <FieldDescription>
                {t(
                  "Lowercase letters, digits and underscores, such as vehicle or forklift.",
                )}
              </FieldDescription>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-tag`}>{t("Tag")}</FieldLabel>
              <Input
                id={`${fieldId}-tag`}
                name="tag"
                maxLength={60}
                autoComplete="off"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-serial`}>
                {t("Serial number")}
              </FieldLabel>
              <Input
                id={`${fieldId}-serial`}
                name="serialNumber"
                maxLength={80}
                autoComplete="off"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Add asset")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
