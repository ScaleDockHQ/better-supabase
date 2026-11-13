"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { UploadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Button } from "@/components/ui/button";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/lib/toast";

import { uploadCustomerLogo } from "../customers-actions";

export function CustomerLogoForm({ customerId }: { customerId: string }) {
  const t = useExtracted("customers");
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const form = useActionForm(uploadCustomerLogo, {
    onSuccess: () => {
      toast.success(t("Logo updated"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <form {...form.formProps} className="space-y-3">
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
      <Button type="submit" variant="outline" size="sm" disabled={form.pending}>
        <UploadIcon />
        {t("Upload logo")}
      </Button>
    </form>
  );
}
