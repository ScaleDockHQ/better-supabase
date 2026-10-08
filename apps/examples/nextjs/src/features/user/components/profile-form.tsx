"use client";

import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { updateProfile } from "../user-actions";

export function ProfileForm({
  fullName,
  email,
}: {
  fullName: string | null;
  email: string | null;
}) {
  const t = useExtracted("user");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(updateProfile, {
    resetOnSuccess: false,
    onSuccess: () => {
      toast.success(t("Profile saved"));
    },
  });
  const error = form.error === undefined ? null : errorMessage(form.error);
  return (
    <form {...form.formProps} className="space-y-6">
      <FieldGroup>
        <Field data-invalid={error ? true : undefined}>
          <FieldLabel htmlFor={`${fieldId}-profile-name`}>
            {t("Full name")}
          </FieldLabel>
          <Input
            id={`${fieldId}-profile-name`}
            name="fullName"
            defaultValue={fullName ?? ""}
            autoComplete="name"
            required
            maxLength={120}
          />
          {error ? <FieldError>{error}</FieldError> : null}
        </Field>
        <Field>
          <FieldLabel htmlFor={`${fieldId}-profile-email`}>
            {t("Email")}
          </FieldLabel>
          <Input
            id={`${fieldId}-profile-email`}
            value={email ?? ""}
            disabled
            readOnly
          />
          <FieldDescription>
            {t("Your sign-in address. It comes from Supabase Auth.")}
          </FieldDescription>
        </Field>
      </FieldGroup>
      <Button type="submit" disabled={form.pending}>
        {t("Save")}
      </Button>
    </form>
  );
}
