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

import { createTarget } from "../crm-actions";
import { FormSelect } from "./form-select";

/** Sets a goal for won deals in a period. */
export function CreateTargetDialog({
  variant = "default",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("crm");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [metric, setMetric] = useState("deals.won_amount");

  const form = useActionForm(createTarget, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Target created"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);
  const amount = metric === "deals.won_amount";

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant={variant} />}>
        <PlusIcon />
        {t("Add target")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add target")}</DialogTitle>
            <DialogDescription>
              {t("Progress counts the deals won in the period.")}
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
                placeholder={t("Q4 new business")}
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-metric`}>
                {t("Measure")}
              </FieldLabel>
              <FormSelect
                id={`${fieldId}-metric`}
                name="metric"
                value={metric}
                onValueChange={setMetric}
                items={[
                  { value: "deals.won_amount", label: t("Amount won") },
                  { value: "deals.won_count", label: t("Deals won") },
                ]}
              />
            </Field>
            <div className="grid gap-3 sm:grid-cols-[1fr_8rem]">
              <Field>
                <FieldLabel htmlFor={`${fieldId}-goal`}>{t("Goal")}</FieldLabel>
                <Input
                  id={`${fieldId}-goal`}
                  name="goal"
                  inputMode={amount ? "decimal" : "numeric"}
                  required
                  pattern={amount ? "\\d+(\\.\\d{1,2})?" : "\\d+"}
                  placeholder={amount ? "100000.00" : "10"}
                />
                <FieldDescription>
                  {amount
                    ? t("In the currency on the right.")
                    : t("A number of deals.")}
                </FieldDescription>
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
                <FieldLabel htmlFor={`${fieldId}-start`}>
                  {t("Starts")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-start`}
                  name="periodStart"
                  type="date"
                  required
                />
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-end`}>{t("Ends")}</FieldLabel>
                <Input
                  id={`${fieldId}-end`}
                  name="periodEnd"
                  type="date"
                  required
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
