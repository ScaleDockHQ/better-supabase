"use client";

import { useExtracted, useLocale } from "next-intl";
import { useActionState, useId } from "react";

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
import { Link } from "@/i18n/navigation";
import { localizedPath } from "@/i18n/routing";
import { loadBrowserClient } from "@/lib/supabase/load-client";

type State =
  | { readonly error: string; readonly email: string }
  | { readonly sent: true }
  | null;

/** Locally the email lands in Mailpit (`supabase status` prints its URL). */
export function ForgotPasswordForm() {
  const t = useExtracted("auth");
  const fieldId = useId();
  const locale = useLocale();

  const [state, submit, pending] = useActionState(
    async (_previous: State, form: FormData): Promise<State> => {
      const email = String(form.get("email"));

      const { supabase } = await loadBrowserClient();

      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}${localizedPath(locale, "/reset-password")}`,
      });

      return error ? { error: error.message, email } : { sent: true };
    },
    null,
  );

  const kept = state && "error" in state ? state : null;
  const error = kept?.error ?? null;

  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle>{t("Reset your password")}</CardTitle>
        <CardDescription>
          {state && "sent" in state
            ? t("If that address has an account, a reset link is on its way.")
            : t("We'll email you a link to choose a new one.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form action={submit}>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-email`}>{t("Email")}</FieldLabel>
              <Input
                id={`${fieldId}-email`}
                name="email"
                type="email"
                defaultValue={kept?.email}
                autoComplete="email"
                required
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Button type="submit" className="w-full" disabled={pending}>
              {t("Send reset link")}
            </Button>
            <Link
              href="/login"
              className="text-center text-sm text-muted-foreground underline-offset-4 hover:underline"
            >
              {t("Back to sign in")}
            </Link>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}
