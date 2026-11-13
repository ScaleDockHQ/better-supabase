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

import type { GiftFormOptions } from "../donations-queries";

import { recordGift } from "../donations-actions";

/** Records a gift from a customer, optionally to a fund. */
export function RecordGiftDialog({ options }: { options: GiftFormOptions }) {
  const t = useExtracted("donations");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(recordGift, {
    onSuccess: () => {
      toast.success(t("Gift recorded"));
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
        {t("Record a gift")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Record a gift")}</DialogTitle>
            <DialogDescription>
              {t("The gift posts on the ledger at once.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel>{t("Donor")}</FieldLabel>
              <Select
                name="donorId"
                required
                items={options.donors.map((row) => ({
                  value: row.id,
                  label: row.name,
                }))}
              >
                <SelectTrigger>
                  <SelectValue placeholder={t("Pick a customer")} />
                </SelectTrigger>
                <SelectContent>
                  {options.donors.map((row) => (
                    <SelectItem key={row.id} value={row.id}>
                      {row.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-amount`}>
                {t("Amount")}
              </FieldLabel>
              <Input
                id={`${fieldId}-amount`}
                name="amount"
                required
                inputMode="decimal"
                pattern="\d+(\.\d{1,2})?"
                placeholder="50.00"
              />
            </Field>
            {options.funds.length > 0 ? (
              <Field>
                <FieldLabel>{t("Fund")}</FieldLabel>
                <Select
                  name="fundId"
                  items={options.funds.map((row) => ({
                    value: row.id,
                    label: row.name,
                  }))}
                >
                  <SelectTrigger>
                    <SelectValue placeholder={t("No fund")} />
                  </SelectTrigger>
                  <SelectContent>
                    {options.funds.map((row) => (
                      <SelectItem key={row.id} value={row.id}>
                        {row.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
            ) : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Record gift")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
