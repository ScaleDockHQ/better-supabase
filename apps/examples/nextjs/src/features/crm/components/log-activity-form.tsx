"use client";

import { useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import type { TimelineSubjectType } from "../crm-queries";

import { logActivity } from "../crm-actions";
import { FormSelect } from "./form-select";

/** Logs a call, email, meeting or note on a contact or a care client. */
export function LogActivityForm({
  subject,
}: {
  subject: { type: TimelineSubjectType; id: string };
}) {
  const t = useExtracted("crm");
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const form = useActionForm(logActivity, {
    resetOnSuccess: true,
    onSuccess: () => {
      toast.success(t("Activity logged"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <form {...form.formProps} className="flex w-full flex-col gap-3">
      <input type="hidden" name="subjectType" value={subject.type} />
      <input type="hidden" name="subjectId" value={subject.id} />
      <div className="grid gap-3 sm:grid-cols-[10rem_1fr]">
        <Field>
          <FieldLabel htmlFor={`${fieldId}-type`}>{t("Type")}</FieldLabel>
          <FormSelect
            id={`${fieldId}-type`}
            name="type"
            defaultValue="call"
            items={[
              { value: "call", label: t("Call") },
              { value: "email", label: t("Email") },
              { value: "meeting", label: t("Meeting") },
              { value: "note", label: t("Note") },
            ]}
          />
        </Field>
        <Field data-invalid={error ? true : undefined}>
          <FieldLabel htmlFor={`${fieldId}-title`}>{t("Summary")}</FieldLabel>
          <Input
            id={`${fieldId}-title`}
            name="title"
            required
            maxLength={200}
            placeholder={t("Intro call about the pilot")}
            aria-invalid={error ? true : undefined}
          />
        </Field>
      </div>
      <Field data-invalid={error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-body`}>{t("Notes")}</FieldLabel>
        <Textarea
          id={`${fieldId}-body`}
          name="body"
          maxLength={2000}
          placeholder={t("What was said, and what happens next")}
        />
        {error ? <FieldError>{error}</FieldError> : null}
      </Field>
      <Button type="submit" size="sm" disabled={form.pending} className="w-fit">
        {t("Log activity")}
      </Button>
    </form>
  );
}
