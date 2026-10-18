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

import type { SelectOption } from "./form-select";

import { createDeal } from "../crm-actions";
import { FormSelect } from "./form-select";

/** Adds a deal to a stage of the pipeline. */
export function CreateDealDialog({
  pipelineId,
  stages,
}: {
  pipelineId: string;
  stages: readonly SelectOption[];
}) {
  const t = useExtracted("crm");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createDeal, {
    onSuccess: (deal) => {
      setOpen(false);
      toast.success(t("{identifier} added", { identifier: deal.identifier }));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);
  const [first] = stages;

  if (!first) {
    return null;
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Add deal")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add deal")}</DialogTitle>
            <DialogDescription>
              {t("The amount and close date feed the forecast and targets.")}
            </DialogDescription>
          </DialogHeader>
          <input type="hidden" name="pipelineId" value={pipelineId} />
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={200}
                placeholder={t("Annual plan for Acme")}
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <div className="grid gap-3 sm:grid-cols-[1fr_8rem]">
              <Field>
                <FieldLabel htmlFor={`${fieldId}-amount`}>
                  {t("Amount")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-amount`}
                  name="amount"
                  inputMode="decimal"
                  required
                  pattern="\d+(\.\d{1,2})?"
                  placeholder="12000.00"
                />
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-currency`}>
                  {t("Currency")}
                </FieldLabel>
                <FormSelect
                  id={`${fieldId}-currency`}
                  name="currency"
                  defaultValue="EUR"
                  items={[
                    { value: "EUR", label: "EUR" },
                    { value: "USD", label: "USD" },
                    { value: "GBP", label: "GBP" },
                  ]}
                />
              </Field>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <Field>
                <FieldLabel htmlFor={`${fieldId}-close`}>
                  {t("Expected close")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-close`}
                  name="closeOn"
                  type="date"
                  required
                />
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-stage`}>
                  {t("Stage")}
                </FieldLabel>
                <FormSelect
                  id={`${fieldId}-stage`}
                  name="stageId"
                  defaultValue={first.value}
                  items={stages}
                />
              </Field>
            </div>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Add")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
