"use client";

import type { DbError } from "better-supabase";

import { useExtracted } from "next-intl";
import { useId, useRef, useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { postIncidentUpdate, resolveIncident } from "../incidents-actions";

type OpenStatus = "investigating" | "identified" | "monitoring";

/** Posts a status update, or resolves the incident with the closing message. */
export function IncidentUpdateForm({ incidentId }: { incidentId: string }) {
  const t = useExtracted("incidents");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const body = useRef<HTMLTextAreaElement>(null);
  const [status, setStatus] = useState<OpenStatus>("investigating");
  const [error, setError] = useState<DbError>();
  const [pending, startTransition] = useTransition();

  const labels: Record<OpenStatus, string> = {
    investigating: t("Investigating"),
    identified: t("Identified"),
    monitoring: t("Monitoring"),
  };

  const send = (resolve: boolean) => {
    const text = body.current?.value ?? "";

    startTransition(async () => {
      const result = resolve
        ? await resolveIncident({ incidentId, body: text })
        : await postIncidentUpdate({ incidentId, status, body: text });

      if (!result.ok) {
        setError(result.error);

        return;
      }

      setError(undefined);
      toast.success(resolve ? t("Incident resolved") : t("Update posted"));

      if (body.current) {
        body.current.value = "";
      }
    });
  };

  return (
    <form
      className="grid gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        send(false);
      }}
    >
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor={`${fieldId}-status`}>{t("Status")}</FieldLabel>
          <Select
            value={status}
            items={labels}
            onValueChange={(next) => {
              if (
                next === "investigating" ||
                next === "identified" ||
                next === "monitoring"
              ) {
                setStatus(next);
              }
            }}
          >
            <SelectTrigger id={`${fieldId}-status`} className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="investigating">
                {labels.investigating}
              </SelectItem>
              <SelectItem value="identified">{labels.identified}</SelectItem>
              <SelectItem value="monitoring">{labels.monitoring}</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <Field data-invalid={error ? true : undefined}>
          <FieldLabel htmlFor={`${fieldId}-body`}>{t("Update")}</FieldLabel>
          <Textarea
            ref={body}
            id={`${fieldId}-body`}
            required
            maxLength={2000}
            rows={3}
          />
          {error ? <FieldError>{errorMessage(error)}</FieldError> : null}
        </Field>
      </FieldGroup>
      <div className="flex items-center gap-2">
        <Button type="submit" size="sm" disabled={pending}>
          {t("Post update")}
        </Button>
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={pending}
          onClick={() => {
            send(true);
          }}
        >
          {t("Resolve")}
        </Button>
      </div>
    </form>
  );
}
