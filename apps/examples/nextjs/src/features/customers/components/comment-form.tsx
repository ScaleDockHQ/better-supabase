"use client";

import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import { addCustomerComment } from "../customer-actions";

export function CommentForm({ customerId }: { customerId: string }) {
  const t = useExtracted("customers");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(addCustomerComment);
  const error = form.error === undefined ? null : errorMessage(form.error);
  return (
    <form {...form.formProps} className="space-y-3">
      <input type="hidden" name="customerId" value={customerId} />
      <Field data-invalid={error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-comment-body`} className="sr-only">
          {t("Comment")}
        </FieldLabel>
        <Textarea
          id={`${fieldId}-comment-body`}
          name="body"
          placeholder={t("Write a comment")}
          required
          maxLength={4000}
          rows={3}
        />
        {error ? <FieldError>{error}</FieldError> : null}
      </Field>
      <Button type="submit" size="sm" disabled={form.pending}>
        {t("Comment")}
      </Button>
    </form>
  );
}
