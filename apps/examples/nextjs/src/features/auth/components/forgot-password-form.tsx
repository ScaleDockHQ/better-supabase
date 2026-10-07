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
import { useSupabase } from "@/lib/hooks";

type State = { readonly error: string } | { readonly sent: true } | null;

/** Locally the email lands in Mailpit (`supabase status` prints its URL). */
export function ForgotPasswordForm() {
  const t = useExtracted("auth");
  const fieldId = useId();
  const locale = useLocale();
  const supabase = useSupabase();
  const [state, submit, pending] = useActionState(
    async (_previous: State, form: FormData): Promise<State> => {
      const { error } = await supabase.auth.resetPasswordForEmail(
        String(form.get("email")),
        {
          redirectTo: `${window.location.origin}/${locale}/reset-password`,
        },
      );
      return error ? { error: error.message } : { sent: true };
    },
    null,
  );
  const error = state && "error" in state ? state.error : null;
  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle className="text-xl">{t("Reset your password")}</CardTitle>
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
              className="text-muted-foreground text-center text-sm underline-offset-4 hover:underline"
            >
              {t("Back to sign in")}
            </Link>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}
