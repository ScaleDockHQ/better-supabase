"use client";

import { useActionForm } from "better-supabase/react";
import { ListOrderedIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId } from "react";

import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
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
import { useErrorMessage } from "@/lib/use-error-message";

import { joinWaitlist } from "../waitlist-actions";

// #region recipe:waitlist-signup
/**
 * Joins the waitlist with an email address and shows the place in line. Joining
 * again with the same address shows the same place.
 */
export function WaitlistSignup() {
  const t = useExtracted("waitlist");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const form = useActionForm(joinWaitlist);

  const error =
    form.error === undefined
      ? null
      : form.error.kind === "validation"
        ? t("Enter a valid email address.")
        : errorMessage(form.error);

  if (form.data) {
    const { position, status } = form.data;

    return (
      <Card data-recipe="waitlist-signup">
        <CardHeader className="text-center">
          <ListOrderedIcon
            aria-hidden="true"
            className="mx-auto size-8 text-primary"
          />
          <CardTitle>
            {status === "waiting" && position !== null
              ? t("You're number {position} in line", {
                  position: String(position),
                })
              : t("You're on the list")}
          </CardTitle>
          <CardDescription>
            {status === "waiting"
              ? t("We'll email you when your spot opens up.")
              : t("Your spot is open. Create your account to get started.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col items-center gap-4">
          <Badge
            variant={status === "waiting" ? "info-light" : "success-light"}
          >
            {status === "waiting" ? t("Waiting") : t("Approved")}
          </Badge>
          {status === "waiting" ? (
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                form.reset();
              }}
            >
              {t("Add another address")}
            </Button>
          ) : (
            <Link href="/signup" className={buttonVariants()}>
              {t("Create your account")}
            </Link>
          )}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card data-recipe="waitlist-signup">
      <CardHeader className="text-center">
        <CardTitle>{t("Join the waitlist")}</CardTitle>
        <CardDescription>
          {t("Acme Cloud opens to new teams in batches. Save your spot.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form {...form.formProps}>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-email`}>{t("Email")}</FieldLabel>
              <Input
                id={`${fieldId}-email`}
                name="email"
                type="email"
                autoComplete="email"
                required
                maxLength={320}
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Button type="submit" className="w-full" disabled={form.pending}>
              {t("Join the waitlist")}
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
// #endregion recipe:waitlist-signup
