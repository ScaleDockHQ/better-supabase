"use client";

import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import type { SelectOption } from "./form-select";

import { linkPerson } from "../crm-actions";
import { FormSelect } from "./form-select";

/** Adds one of the organization's people to a company. */
export function LinkPersonForm({
  companyId,
  people,
}: {
  companyId: string;
  people: readonly SelectOption[];
}) {
  const t = useExtracted("crm");
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const form = useActionForm(linkPerson, {
    resetOnSuccess: true,
    onSuccess: () => {
      toast.success(t("Person added to the company"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);
  const [first] = people;

  if (!first) {
    return null;
  }

  return (
    <form {...form.formProps} className="flex flex-col gap-3">
      <input type="hidden" name="companyId" value={companyId} />
      <Field data-invalid={error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-person`}>{t("Person")}</FieldLabel>
        <FormSelect
          id={`${fieldId}-person`}
          name="personId"
          size="sm"
          defaultValue={first.value}
          items={people}
        />
        {error ? <FieldError>{error}</FieldError> : null}
      </Field>
      <Field>
        <FieldLabel htmlFor={`${fieldId}-role`}>{t("Role")}</FieldLabel>
        <Input
          id={`${fieldId}-role`}
          name="role"
          maxLength={200}
          placeholder={t("Buyer")}
        />
      </Field>
      <Button
        type="submit"
        size="sm"
        variant="outline"
        disabled={form.pending}
        className="w-fit"
      >
        {t("Add to company")}
      </Button>
    </form>
  );
}
