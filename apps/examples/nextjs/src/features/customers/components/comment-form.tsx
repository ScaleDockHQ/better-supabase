"use client";

import { useExtracted } from "next-intl";
import { useActionState, useId, useRef } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import { addCustomerComment } from "../customer-actions";

export function CommentForm({ customerId }: { customerId: string }) {
  const t = useExtracted("customers");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useRef<HTMLFormElement>(null);
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, data: FormData) => {
      const result = await addCustomerComment(data);
      if (!result.ok) return errorMessage(result.error);
      form.current?.reset();
      return null;
    },
    null,
  );
  return (
    <form ref={form} action={submit} className="space-y-3">
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
      <Button type="submit" size="sm" disabled={pending}>
        {t("Comment")}
      </Button>
    </form>
  );
}
