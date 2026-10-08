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

import { updateOrganization } from "../organization-actions";

export function OrganizationForm({
  name,
  slug,
  canEdit,
}: {
  name: string;
  slug: string;
  canEdit: boolean;
}) {
  const t = useExtracted("organization");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(updateOrganization, {
    resetOnSuccess: false,
    onSuccess: () => {
      toast.success(t("Organization saved"));
    },
  });
  const error =
    form.error === undefined
      ? null
      : form.error.kind === "conflict"
        ? t("That URL is taken. Pick another one.")
        : errorMessage(form.error);
  return (
    <form {...form.formProps} className="space-y-6">
      <fieldset disabled={!canEdit}>
        <FieldGroup>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-organization-name`}>
              {t("Name")}
            </FieldLabel>
            <Input
              id={`${fieldId}-organization-name`}
              name="name"
              defaultValue={name}
              required
              minLength={2}
              maxLength={80}
            />
          </Field>
          <Field data-invalid={error ? true : undefined}>
            <FieldLabel htmlFor={`${fieldId}-organization-slug`}>
              {t("URL")}
            </FieldLabel>
            <Input
              id={`${fieldId}-organization-slug`}
              name="slug"
              defaultValue={slug}
              required
              pattern="[a-z0-9][a-z0-9\-]*[a-z0-9]"
              maxLength={48}
              aria-invalid={error ? true : undefined}
            />
            <FieldDescription>
              {t("Lowercase letters, numbers and dashes.")}
            </FieldDescription>
            {error ? <FieldError>{error}</FieldError> : null}
          </Field>
        </FieldGroup>
      </fieldset>
      {canEdit ? (
        <Button type="submit" disabled={form.pending}>
          {t("Save")}
        </Button>
      ) : (
        <p className="text-muted-foreground text-sm">
          {t("Only owners and admins can change the organization.")}
        </p>
      )}
    </form>
  );
}
