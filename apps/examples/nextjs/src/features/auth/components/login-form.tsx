"use client";

import { useSessionChange } from "better-supabase/next/client";
import { useExtracted, useLocale } from "next-intl";
import { useRouter } from "next/navigation";
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
import { sessionChanged } from "@/features/user/user-actions";
import { Link } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";

import { safeNext } from "../safe-next";

export function LoginForm() {
  const t = useExtracted("auth");
  const fieldId = useId();
  const locale = useLocale();
  const supabase = useSupabase();
  const changeSession = useSessionChange(sessionChanged, useRouter());
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: String(form.get("email")),
        password: String(form.get("password")),
      });
      if (signInError) {
        return signInError.code === "invalid_credentials"
          ? t("That email and password don't match.")
          : signInError.message;
      }
      // A verified factor means this session must reach aal2 first.
      const { data: aal } =
        await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      const next = safeNext(`/${locale}`);
      await changeSession(
        aal?.nextLevel === "aal2" && aal.currentLevel !== "aal2"
          ? `/${locale}/mfa?next=${encodeURIComponent(next)}`
          : next,
      );
      return null;
    },
    null,
  );
  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle className="text-xl">{t("Welcome back")}</CardTitle>
        <CardDescription>{t("Sign in to your organization.")}</CardDescription>
      </CardHeader>
      <CardContent>
        <form action={submit}>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-email`}>{t("Email")}</FieldLabel>
              <Input
                id={`${fieldId}-email`}
                name="email"
                type="email"
                placeholder="you@acme.test"
                autoComplete="email"
                required
              />
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <div className="flex items-center">
                <FieldLabel htmlFor={`${fieldId}-password`}>
                  {t("Password")}
                </FieldLabel>
                <Link
                  href="/forgot-password"
                  className="text-muted-foreground ml-auto text-sm underline-offset-4 hover:underline"
                >
                  {t("Forgot your password?")}
                </Link>
              </div>
              <Input
                id={`${fieldId}-password`}
                name="password"
                type="password"
                autoComplete="current-password"
                required
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Button type="submit" className="w-full" disabled={pending}>
              {t("Sign in")}
            </Button>
            <p className="text-muted-foreground text-center text-sm">
              {t("No account yet?")}{" "}
              <Link
                href="/signup"
                className="text-foreground underline underline-offset-4"
              >
                {t("Sign up")}
              </Link>
            </p>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}
