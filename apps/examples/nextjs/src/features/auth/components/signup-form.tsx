"use client";

import { useSessionChange } from "better-supabase/next/client";
import { initBotId } from "botid/client/core";
import { MailCheckIcon } from "lucide-react";
import { useExtracted, useLocale } from "next-intl";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useId } from "react";

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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { sessionChanged } from "@/features/user/user-actions";
import { Link } from "@/i18n/navigation";
import { localizedPath } from "@/i18n/routing";

import { signUp } from "../auth-actions";
import { safeNext } from "../safe-next";

type State =
  | {
      readonly error: string;
      readonly fullName: string;
      readonly email: string;
    }
  | { readonly confirm: string }
  | null;

/**
 * The `signUp` Server Action runs BotID's check before it calls Auth. New users
 * have no organization until they create one or accept an invitation.
 */
export function SignupForm() {
  const t = useExtracted("auth");
  const tSignup = useExtracted("signup");
  const fieldId = useId();
  const locale = useLocale();
  const router = useRouter();
  const changeSession = useSessionChange(sessionChanged, router);

  // BotID loads here, not in instrumentation-client.ts, so only this route
  // carries its script. The Server Action posts to this page.
  useEffect(() => {
    initBotId({
      protect: [{ path: localizedPath(locale, "/signup"), method: "POST" }],
    });
  }, [locale]);

  const [state, submit, pending] = useActionState(
    async (_previous: State, form: FormData): Promise<State> => {
      const email = String(form.get("email"));
      const fullName = String(form.get("fullName"));

      const result = await signUp({
        email,
        password: String(form.get("password")),
        fullName,
        locale,
      });

      if (!result.ok) {
        const { code, hint, message } = result.error;

        return {
          error:
            code === "weak_password"
              ? tSignup(
                  "Use a longer password with upper and lower case letters and digits.",
                )
              : hint === "BOT_DETECTED"
                ? tSignup(
                    "This request looks automated. Try again from a browser.",
                  )
                : message,
          fullName,
          email,
        };
      }

      // With email confirmations on, there is no session until the link is
      // opened; an email that already has an account gets the same screen.
      if (result.data === null || "existingAccount" in result.data) {
        return { confirm: email };
      }

      await changeSession(safeNext(result.data.redirectTo));

      return null;
    },
    null,
  );

  if (state && "confirm" in state) {
    return (
      <Card>
        <CardHeader className="text-center">
          <MailCheckIcon className="mx-auto size-8 text-primary" />
          <CardTitle>{t("Check your email")}</CardTitle>
          <CardDescription>
            {t("We sent a confirmation link to {email}.", {
              email: state.confirm,
            })}
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  const kept = state && "error" in state ? state : null;
  const error = kept?.error ?? null;

  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle>{t("Create your account")}</CardTitle>
        <CardDescription>
          {t("Then create an organization or accept an invitation.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form action={submit}>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-full-name`}>
                {t("Full name")}
              </FieldLabel>
              <Input
                id={`${fieldId}-full-name`}
                name="fullName"
                defaultValue={kept?.fullName}
                autoComplete="name"
                required
                maxLength={80}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-email`}>{t("Email")}</FieldLabel>
              <Input
                id={`${fieldId}-email`}
                name="email"
                type="email"
                defaultValue={kept?.email}
                autoComplete="email"
                required
              />
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-password`}>
                {t("Password")}
              </FieldLabel>
              <Input
                id={`${fieldId}-password`}
                name="password"
                type="password"
                autoComplete="new-password"
                minLength={8}
                required
              />
              <FieldDescription>{t("At least 8 characters.")}</FieldDescription>
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Button type="submit" className="w-full" disabled={pending}>
              {t("Create account")}
            </Button>
            <p className="text-center text-sm text-muted-foreground">
              {t("Already have an account?")}{" "}
              <Link
                href="/login"
                className="text-foreground underline underline-offset-4"
              >
                {t("Sign in")}
              </Link>
            </p>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}
