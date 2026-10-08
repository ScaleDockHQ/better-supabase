"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";
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
  const save = useAction(setWeeklyDigest, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
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
        checked={save.pendingInput?.enabled ?? enabled}
        onCheckedChange={(checked: boolean) => {
          void save.run({ enabled: checked });
        }}
      />
    </Field>
  );
}
