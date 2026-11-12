"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/lib/toast";

import { recordRentPayment } from "../leases-actions";

/** Records a rent payment against the lease's balance due. */
export function RecordPaymentForm({ leaseId }: { leaseId: string }) {
  const t = useExtracted("leases");
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const form = useActionForm(recordRentPayment, {
    onSuccess: () => {
      toast.success(t("Payment recorded"));
      form.reset();
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <form {...form.formProps} className="flex items-end gap-2">
      <input type="hidden" name="leaseId" value={leaseId} />
      <Field data-invalid={error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-amount`}>{t("Payment")}</FieldLabel>
        <Input
          id={`${fieldId}-amount`}
          name="amount"
          required
          inputMode="decimal"
          pattern="\d+(\.\d{1,2})?"
          placeholder="1200.00"
        />
        {error ? <FieldError>{error}</FieldError> : null}
      </Field>
      <Button type="submit" size="sm" disabled={form.pending}>
        {t("Record payment")}
      </Button>
    </form>
  );
}
