"use client";

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
import { isLocalizedRoute, Link } from "@/i18n/navigation";

import { signInWithPassword } from "../auth-actions";

/**
 * What a rejected sign-in keeps, so the email the user typed stays in the
 * field.
 */
type LoginState = { readonly email: string; readonly error: string | null };

export function LoginForm() {
  const t = useExtracted("auth");
  const fieldId = useId();
  const locale = useLocale();
  const router = useRouter();

  const [state, submit, pending] = useActionState(
    async (_previous: LoginState, form: FormData): Promise<LoginState> => {
      const email = String(form.get("email"));

      const result = await signInWithPassword({
        email,
        password: String(form.get("password")),
        next: new URLSearchParams(window.location.search).get("next"),
        locale,
      });

      if (!result.ok) {
        return {
          email,
          error:
            result.error.code === "invalid_credentials"
              ? t("That email and password don't match.")
              : result.error.message,
        };
      }

      const { redirectTo, mfa } = result.data;

      const target = mfa
        ? `/${locale}/mfa?next=${encodeURIComponent(redirectTo)}`
        : redirectTo;

      router.replace(isLocalizedRoute(target) ? target : `/${locale}`);

      return { email, error: null };
    },
    { email: "", error: null },
  );

  const { error } = state;

  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle>{t("Welcome back")}</CardTitle>
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
                defaultValue={state.email}
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
                  className="ml-auto text-sm text-muted-foreground underline-offset-4 hover:underline"
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
            <p className="text-center text-sm text-muted-foreground">
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
