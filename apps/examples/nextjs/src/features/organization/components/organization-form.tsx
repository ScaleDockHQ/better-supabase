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
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const result = await updateOrganization(form);
      if (!result.ok) {
        return result.error.kind === "conflict"
          ? t("That URL is taken. Pick another one.")
          : errorMessage(result.error);
      }
      toast.success(t("Organization saved"));
      return null;
    },
    null,
  );
  return (
    <form action={submit} className="space-y-6">
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
        <Button type="submit" disabled={pending}>
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
