"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

import { Badge } from "@/components/reui/badge";
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
  FieldLabel,
} from "@/components/ui/field";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { savePromptVersion } from "../prompts-actions";

const PLACEHOLDER = /\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/g;

/**
 * The `{{name}}` placeholders of a template, once each, as the block finds
 * them.
 */
const variablesOf = (template: string): string[] => [
  ...new Set(
    [...template.matchAll(PLACEHOLDER)].map((match) => match[1] ?? ""),
  ),
];

/** The template editor: save as the next version, optionally going live at once. */
export function PromptEditor({
  name,
  initial,
  next,
}: {
  name: string;
  initial: string;
  next: number;
}) {
  const t = useExtracted("prompts");
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  const [template, setTemplate] = useState(initial);
  const variables = variablesOf(template);

  const save = useAction(savePromptVersion, {
    onSuccess: (version) => {
      toast.success(t("Saved version {version, number}", { version }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Template")}</CardTitle>
        <CardDescription>
          {t(
            "Saving creates version {version, number}. Earlier versions never change.",
            { version: next },
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form
          className="flex flex-col gap-4"
          onSubmit={(event) => {
            event.preventDefault();
          }}
        >
          <Field>
            <FieldLabel htmlFor={`${fieldId}-template`}>
              {t("Template")}
            </FieldLabel>
            <Textarea
              id={`${fieldId}-template`}
              value={template}
              rows={12}
              className="font-mono"
              onChange={(event) => {
                setTemplate(event.target.value);
              }}
            />
            <FieldDescription className="flex flex-wrap items-center gap-1">
              {variables.length === 0
                ? t("No variables. Put a name in double braces to add one.")
                : t("Variables:")}
              {variables.map((variable) => (
                <Badge key={variable} variant="secondary">
                  {variable}
                </Badge>
              ))}
            </FieldDescription>
            {save.error === undefined ? null : (
              <FieldError>{errorMessage(save.error)}</FieldError>
            )}
          </Field>
          <div className="flex flex-wrap justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              disabled={save.pending || template.trim() === ""}
              onClick={() => {
                void save.run({ name, template });
              }}
            >
              {t("Save version")}
            </Button>
            <Button
              type="button"
              disabled={save.pending || template.trim() === ""}
              onClick={() => {
                void save.run({ name, template, label: "production" });
              }}
            >
              {t("Save and go live")}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
