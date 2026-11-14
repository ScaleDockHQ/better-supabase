"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

import { connectInstallation } from "../marketplace-actions";

/** Links a Vercel configuration id to the organization. */
export function ConnectInstallation() {
  const t = useExtracted("marketplace");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(connectInstallation);
  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Connect an installation")}</CardTitle>
        <CardDescription>
          {t(
            "Enter the configuration id Vercel shows for the installation. The organization is linked to it, and its resources are listed on this page.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form {...form.formProps} className="flex items-end gap-2">
          <Field data-invalid={error ? true : undefined} className="flex-1">
            <FieldLabel htmlFor={`${fieldId}-configuration`}>
              {t("Configuration id")}
            </FieldLabel>
            <Input
              id={`${fieldId}-configuration`}
              name="configurationId"
              required
              autoComplete="off"
              placeholder="icfg_..."
            />
            {error ? <FieldError>{error}</FieldError> : null}
          </Field>
          <Button type="submit" disabled={form.pending}>
            {t("Connect")}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
