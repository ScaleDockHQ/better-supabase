"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
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

import type { LeaseFormOptions } from "../leases-queries";

import { createLease } from "../leases-actions";

/** Drafts a lease of an asset to a customer. */
export function CreateLeaseDialog({ options }: { options: LeaseFormOptions }) {
  const t = useExtracted("leases");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createLease, {
    onSuccess: () => {
      toast.success(t("Lease drafted"));
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
        {t("New lease")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New lease")}</DialogTitle>
            <DialogDescription>
              {t("A draft lease starts when you activate it.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel>{t("Unit")}</FieldLabel>
              <Select
                name="unitId"
                required
                items={options.units.map((unit) => ({
                  value: unit.id,
                  label: unit.name,
                }))}
              >
                <SelectTrigger>
                  <SelectValue placeholder={t("Pick an asset")} />
                </SelectTrigger>
                <SelectContent>
                  {options.units.map((unit) => (
                    <SelectItem key={unit.id} value={unit.id}>
                      {unit.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel>{t("Tenant")}</FieldLabel>
              <Select
                name="customerId"
                required
                items={options.parties.map((party) => ({
                  value: party.id,
                  label: party.name,
                }))}
              >
                <SelectTrigger>
                  <SelectValue placeholder={t("Pick a customer")} />
                </SelectTrigger>
                <SelectContent>
                  {options.parties.map((party) => (
                    <SelectItem key={party.id} value={party.id}>
                      {party.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-start`}>
                {t("Starts on")}
              </FieldLabel>
              <Input
                id={`${fieldId}-start`}
                name="startsOn"
                type="date"
                required
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-rent`}>
                {t("Monthly rent")}
              </FieldLabel>
              <Input
                id={`${fieldId}-rent`}
                name="rent"
                required
                inputMode="decimal"
                pattern="\d+(\.\d{1,2})?"
                placeholder="1200.00"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-deposit`}>
                {t("Deposit")}
              </FieldLabel>
              <Input
                id={`${fieldId}-deposit`}
                name="deposit"
                inputMode="decimal"
                pattern="\d+(\.\d{1,2})?"
                placeholder="2400.00"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Draft lease")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
