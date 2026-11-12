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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ClaimFormOptions } from "../warranty-queries";

import { createClaim } from "../warranty-actions";

/** Files a draft warranty claim on an asset. */
export function CreateClaimDialog({ options }: { options: ClaimFormOptions }) {
  const t = useExtracted("warranty");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createClaim, {
    onSuccess: () => {
      toast.success(t("Claim filed"));
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
        {t("File a claim")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("File a claim")}</DialogTitle>
            <DialogDescription>
              {t("A draft claim is sent to the maker when you submit it.")}
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
                autoComplete="off"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel>{t("Asset")}</FieldLabel>
              <Select
                name="assetId"
                required
                items={options.assets.map((asset) => ({
                  value: asset.id,
                  label: asset.name,
                }))}
              >
                <SelectTrigger>
                  <SelectValue placeholder={t("Pick an asset")} />
                </SelectTrigger>
                <SelectContent>
                  {options.assets.map((asset) => (
                    <SelectItem key={asset.id} value={asset.id}>
                      {asset.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-amount`}>
                {t("Covered amount")}
              </FieldLabel>
              <Input
                id={`${fieldId}-amount`}
                name="amount"
                required
                inputMode="decimal"
                pattern="\d+(\.\d{1,2})?"
                placeholder="450.00"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-maker`}>
                {t("Manufacturer")}
              </FieldLabel>
              <Input
                id={`${fieldId}-maker`}
                name="manufacturer"
                maxLength={200}
                autoComplete="off"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("File claim")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
