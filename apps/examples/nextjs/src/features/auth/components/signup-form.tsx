"use client";

import { useSessionChange } from "better-supabase/next/client";
import { MailCheckIcon } from "lucide-react";
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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { sessionChanged } from "@/features/user/user-actions";
import { Link } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";

import { safeNext } from "../safe-next";

type State = { readonly error: string } | { readonly confirm: string } | null;

/**
 * `full_name` goes to `raw_user_meta_data`, which the profiles module copies
 * into the profile. New users have no organization until they create one or
 * accept an invitation.
 */
export function SignupForm() {
  const t = useExtracted("auth");
  const fieldId = useId();
  const locale = useLocale();
  const supabase = useSupabase();
  const router = useRouter();
  const changeSession = useSessionChange(sessionChanged, router);
  const [state, submit, pending] = useActionState(
    async (_previous: State, form: FormData): Promise<State> => {
      const email = String(form.get("email"));
      const { data, error } = await supabase.auth.signUp({
        email,
        password: String(form.get("password")),
        options: {
          data: { full_name: String(form.get("fullName")) },
          emailRedirectTo: `${window.location.origin}/${locale}`,
        },
      });
      if (error) return { error: error.message };
      // With email confirmations on, there is no session until the link is opened.
      if (!data.session) return { confirm: email };
      await changeSession(safeNext(`/${locale}`));
      return null;
    },
    null,
  );
  if (state && "confirm" in state) {
    return (
      <Card>
        <CardHeader className="text-center">
          <MailCheckIcon className="text-primary mx-auto size-8" />
          <CardTitle className="text-xl">{t("Check your email")}</CardTitle>
          <CardDescription>
            {t("We sent a confirmation link to {email}.", {
              email: state.confirm,
            })}
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }
  const error = state && "error" in state ? state.error : null;
  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle className="text-xl">{t("Create your account")}</CardTitle>
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
            <p className="text-muted-foreground text-center text-sm">
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
