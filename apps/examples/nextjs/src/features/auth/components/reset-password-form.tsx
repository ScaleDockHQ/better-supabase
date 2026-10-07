"use client";

import { useExtracted } from "next-intl";
import { useActionState, useId } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { sessionChanged } from "@/features/user/user-actions";
import { useRouter } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";

/**
 * The reset link signs the user in (the browser client exchanges its code),
 * so the new password is a plain `updateUser`.
 */
export function ResetPasswordForm() {
  const t = useExtracted("auth");
  const fieldId = useId();
  const supabase = useSupabase();
  const router = useRouter();
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const password = String(form.get("password"));
      if (password !== String(form.get("confirm")))
        return t("The passwords don't match.");
      const { error: updateError } = await supabase.auth.updateUser({
        password,
      });
      if (updateError) {
        return updateError.code === "session_not_found" ||
          updateError.name === "AuthSessionMissingError"
          ? t("This link has expired. Ask for a new one.")
          : updateError.message;
      }
      await sessionChanged();
      toast.success(t("Password changed"));
      router.push("/");
      return null;
    },
    null,
  );
  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle className="text-xl">{t("Choose a new password")}</CardTitle>
        <CardDescription>{t("You stay signed in afterwards.")}</CardDescription>
      </CardHeader>
      <CardContent>
        <form action={submit}>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-password`}>
                {t("New password")}
              </FieldLabel>
              <Input
                id={`${fieldId}-password`}
                name="password"
                type="password"
                autoComplete="new-password"
                minLength={8}
                required
              />
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-confirm`}>
                {t("Repeat it")}
              </FieldLabel>
              <Input
                id={`${fieldId}-confirm`}
                name="confirm"
                type="password"
                autoComplete="new-password"
                minLength={8}
                required
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Button type="submit" className="w-full" disabled={pending}>
              {t("Change password")}
            </Button>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}
