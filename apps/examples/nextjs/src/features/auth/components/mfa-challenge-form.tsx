"use client";

import { useSessionChange } from "better-supabase/next/client";
import { useExtracted, useLocale } from "next-intl";
import { useRouter } from "next/navigation";
import { useId, useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSlot,
} from "@/components/ui/input-otp";
import { sessionChanged } from "@/features/user/user-actions";
import { useSupabase } from "@/lib/hooks";

import { safeNext } from "../safe-next";

/** The second step of sign-in: raises the session from `aal1` to `aal2`. */
export function MfaChallengeForm() {
  const t = useExtracted("auth");
  const fieldId = useId();
  const locale = useLocale();
  const supabase = useSupabase();
  const router = useRouter();
  const changeSession = useSessionChange(sessionChanged, router);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const verify = () => {
    startTransition(async () => {
      const { data: factors } = await supabase.auth.mfa.listFactors();
      const factor = factors?.totp[0];
      if (!factor) {
        router.push(safeNext(`/${locale}`));
        return;
      }
      const { error: verifyError } = await supabase.auth.mfa.challengeAndVerify(
        {
          factorId: factor.id,
          code,
        },
      );
      if (verifyError) {
        setError(t("That code didn't work. Try the next one."));
        return;
      }
      await changeSession(safeNext(`/${locale}`));
    });
  };
  return (
    <Card>
      <CardHeader className="text-center">
        <CardTitle className="text-xl">
          {t("Two-factor authentication")}
        </CardTitle>
        <CardDescription>
          {t("Enter the code from your authenticator app.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form
          className="flex flex-col items-center gap-6"
          onSubmit={(event) => {
            event.preventDefault();
            verify();
          }}
        >
          <Field
            data-invalid={error ? true : undefined}
            className="items-center"
          >
            <FieldLabel htmlFor={`${fieldId}-mfa-code`} className="sr-only">
              {t("Code")}
            </FieldLabel>
            <InputOTP
              id={`${fieldId}-mfa-code`}
              maxLength={6}
              value={code}
              onChange={setCode}
            >
              <InputOTPGroup>
                {Array.from({ length: 6 }, (_, index) => (
                  <InputOTPSlot key={index} index={index} />
                ))}
              </InputOTPGroup>
            </InputOTP>
            {error ? <FieldError>{error}</FieldError> : null}
          </Field>
          <Button
            type="submit"
            className="w-full"
            disabled={pending || code.length !== 6}
          >
            {t("Verify")}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
