"use client";

import { useExtracted } from "next-intl";
import { useActionState, useId } from "react";
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
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const result = await updateProfile(form);
      if (!result.ok) return errorMessage(result.error);
      toast.success(t("Profile saved"));
      return null;
    },
    null,
  );
  return (
    <form action={submit} className="space-y-6">
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
      <Button type="submit" disabled={pending}>
        {t("Save")}
      </Button>
    </form>
  );
}
