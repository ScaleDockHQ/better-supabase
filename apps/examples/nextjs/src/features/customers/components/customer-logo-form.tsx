"use client";

import { UploadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useActionState, useId } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { uploadCustomerLogo } from "../customer-actions";

export function CustomerLogoForm({ customerId }: { customerId: string }) {
  const t = useExtracted("customers");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const result = await uploadCustomerLogo(form);
      if (!result.ok) return errorMessage(result.error);
      toast.success(t("Logo updated"));
      return null;
    },
    null,
  );
  return (
    <form action={submit} className="space-y-3">
      <input type="hidden" name="customerId" value={customerId} />
      <Field data-invalid={error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-customer-logo`}>
          {t("Logo")}
        </FieldLabel>
        <Input
          id={`${fieldId}-customer-logo`}
          type="file"
          name="logo"
          accept="image/png,image/jpeg,image/webp"
          required
        />
        <FieldDescription>
          {t("PNG, JPEG or WebP. Stored in the public logos bucket.")}
        </FieldDescription>
        {error ? <FieldError>{error}</FieldError> : null}
      </Field>
      <Button type="submit" variant="outline" size="sm" disabled={pending}>
        <UploadIcon />
        {t("Upload logo")}
      </Button>
    </form>
  );
}
