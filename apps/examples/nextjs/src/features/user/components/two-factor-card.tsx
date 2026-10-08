"use client";

import { useSessionChange } from "better-supabase/next/client";
import { ShieldCheckIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import Image from "next/image";
import { useId, useState, useTransition } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from "@/components/ui/field";
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSlot,
} from "@/components/ui/input-otp";
import { useSupabase } from "@/lib/hooks";

import type { AuthRead } from "../security-queries";

import { sessionChanged } from "../user-actions";

interface Enrollment {
  readonly factorId: string;
  readonly qrCode: string;
  readonly secret: string;
}

/**
 * TOTP through Supabase Auth MFA. The server reads the verified factor
 * (`getTotpFactorId`), so it is in the prefetched page; enrolling and
 * verifying run in the browser. A verified factor raises the session to
 * `aal2`, which `deleteMyAccount` and `DELETE /api/customers/:id` require.
 */
export function TwoFactorCard({
  initial,
}: {
  readonly initial: AuthRead<string | null>;
}) {
  const t = useExtracted("security");
  const fieldId = useId();
  const supabase = useSupabase();
  const changeSession = useSessionChange(sessionChanged);
  const refreshAndChange = useSessionChange(sessionChanged, undefined, {
    refreshToken: supabase,
  });
  const [factorId, setFactorId] = useState(initial.ok ? initial.value : null);
  const readError = initial.ok ? null : initial.error;
  const [enrollment, setEnrollment] = useState<Enrollment | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const enroll = () => {
    startTransition(async () => {
      setError(null);
      const { data, error: enrollError } = await supabase.auth.mfa.enroll({
        factorType: "totp",
        friendlyName: `Acme Cloud ${new Date().toISOString().slice(0, 10)}`,
      });
      if (enrollError) {
        setError(enrollError.message);
        return;
      }
      setEnrollment({
        factorId: data.id,
        qrCode: data.totp.qr_code,
        secret: data.totp.secret,
      });
    });
  };

  const verify = () => {
    if (!enrollment) return;
    startTransition(async () => {
      const { error: verifyError } = await supabase.auth.mfa.challengeAndVerify(
        {
          factorId: enrollment.factorId,
          code,
        },
      );
      if (verifyError) {
        setError(t("That code didn't work. Try the next one."));
        return;
      }
      await changeSession();
      setFactorId(enrollment.factorId);
      setEnrollment(null);
      setCode("");
      toast.success(t("Two-factor authentication is on"));
    });
  };

  const remove = () => {
    if (!factorId) return;
    startTransition(async () => {
      const { error: removeError } = await supabase.auth.mfa.unenroll({
        factorId,
      });
      if (removeError) {
        toast.error(removeError.message);
        return;
      }
      await refreshAndChange();
      setFactorId(null);
      toast.success(t("Two-factor authentication is off"));
    });
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Two-factor authentication")}</CardTitle>
        <CardDescription>
          {t(
            "An authenticator app code at sign-in. Needed to delete your account.",
          )}
        </CardDescription>
        <CardAction>
          {readError ? null : factorId ? (
            <Badge data-testid="mfa-status">
              <ShieldCheckIcon />
              {t("On")}
            </Badge>
          ) : (
            <Badge variant="secondary" data-testid="mfa-status">
              {t("Off")}
            </Badge>
          )}
        </CardAction>
      </CardHeader>
      <CardContent className="space-y-4">
        {readError ? (
          <p className="text-destructive text-sm">{readError}</p>
        ) : enrollment ? (
          <div className="flex flex-col gap-6 sm:flex-row sm:items-start">
            {/* An SVG data URL from Supabase Auth: nothing to optimize. */}
            <Image
              src={enrollment.qrCode}
              width={160}
              height={160}
              unoptimized
              alt={t("QR code for your authenticator app")}
              className="rounded-lg bg-white p-2"
            />
            <div className="space-y-4">
              <Field data-invalid={error ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-totp-code`}>
                  {t("Code from the app")}
                </FieldLabel>
                <InputOTP
                  id={`${fieldId}-totp-code`}
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
                <FieldDescription>
                  {t("Or enter this key by hand: {secret}", {
                    secret: enrollment.secret,
                  })}
                </FieldDescription>
                {error ? <FieldError>{error}</FieldError> : null}
              </Field>
              <div className="flex gap-2">
                <Button
                  onClick={verify}
                  disabled={pending || code.length !== 6}
                >
                  {t("Verify")}
                </Button>
                <Button
                  variant="outline"
                  onClick={() => {
                    setEnrollment(null);
                  }}
                >
                  {t("Cancel")}
                </Button>
              </div>
            </div>
          </div>
        ) : factorId ? (
          <Button variant="outline" onClick={remove} disabled={pending}>
            {t("Turn off")}
          </Button>
        ) : (
          <>
            <Button onClick={enroll} disabled={pending}>
              {t("Set up")}
            </Button>
            {error ? <p className="text-destructive text-sm">{error}</p> : null}
          </>
        )}
      </CardContent>
    </Card>
  );
}
