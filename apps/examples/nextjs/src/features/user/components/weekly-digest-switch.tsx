"use client";

import { useExtracted } from "next-intl";
import { useId, useOptimistic, useTransition } from "react";
import { toast } from "sonner";

import {
  Field,
  FieldContent,
  FieldDescription,
  FieldLabel,
} from "@/components/ui/field";
import { Switch } from "@/components/ui/switch";
import { useErrorMessage } from "@/lib/use-error-message";

import { setWeeklyDigest } from "../user-actions";

export function WeeklyDigestSwitch({ enabled }: { enabled: boolean }) {
  const t = useExtracted("user");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [optimistic, setOptimistic] = useOptimistic(enabled);
  const [, startTransition] = useTransition();
  return (
    <Field orientation="horizontal">
      <FieldContent>
        <FieldLabel htmlFor={`${fieldId}-weekly-digest`}>
          {t("Weekly digest")}
        </FieldLabel>
        <FieldDescription>
          {t(
            "A Monday summary of your customers. Saved by the settings module.",
          )}
        </FieldDescription>
      </FieldContent>
      <Switch
        id={`${fieldId}-weekly-digest`}
        checked={optimistic}
        onCheckedChange={(checked: boolean) => {
          startTransition(async () => {
            setOptimistic(checked);
            const result = await setWeeklyDigest({ enabled: checked });
            if (!result.ok) toast.error(errorMessage(result.error));
          });
        }}
      />
    </Field>
  );
}
