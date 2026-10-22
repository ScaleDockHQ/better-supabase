"use client";

import type { FormField } from "better-supabase/blocks/forms";

import { useAction } from "better-supabase/react";
import { SendIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { CardContent, CardFooter } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import { submitQuiz } from "../courses-actions";

type Answer =
  | { readonly kind: "text"; readonly text: string }
  | { readonly kind: "check"; readonly checked: boolean }
  | { readonly kind: "picks"; readonly picks: readonly string[] };

type Payload = Record<string, string | number | boolean | string[]>;

const NPS_SCALE = Array.from({ length: 11 }, (_, score) => String(score));

function optionItems(field: FormField) {
  return field.type === "nps"
    ? NPS_SCALE.map((score) => ({ value: score, label: score }))
    : (field.options ?? []).map((option) => ({
        value: option.value,
        label: option.label,
      }));
}

const NUMERIC = new Set(["number", "integer", "nps"]);

/** Inputs hold text; the database grades numbers as numbers. */
function payloadOf(
  fields: readonly FormField[],
  answers: Readonly<Record<string, Answer>>,
) {
  const payload: Payload = {};

  for (const field of fields) {
    const answer = answers[field.key];

    if (answer === undefined) {
      continue;
    }

    switch (answer.kind) {
      case "text": {
        if (answer.text !== "") {
          payload[field.key] = NUMERIC.has(field.type ?? "text")
            ? Number(answer.text)
            : answer.text;
        }

        break;
      }

      case "check": {
        payload[field.key] = answer.checked;
        break;
      }

      case "picks": {
        payload[field.key] = [...answer.picks];
        break;
      }

      default: {
        const unhandled: never = answer;

        return unhandled;
      }
    }
  }

  return payload;
}

/** A quiz lesson's questions. The database scores the answers on submit. */
export function QuizForm({
  lessonId,
  fields,
}: {
  lessonId: string;
  fields: readonly FormField[];
}) {
  const t = useExtracted("courses");
  const message = useErrorMessage();
  const formId = useId();
  const [answers, setAnswers] = useState<Record<string, Answer>>({});

  const submit = useAction(submitQuiz, {
    onSuccess: (data) => {
      const score = t("{score, number} of {max, number}", {
        score: data.score ?? 0,
        max: data.max ?? 0,
      });

      if (data.passed) {
        toast.success(t("Passed: {score}", { score }));
      } else {
        toast.error(t("Not passed yet: {score}", { score }));
      }
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  const set = (key: string, value: Answer) => {
    setAnswers((current) => ({ ...current, [key]: value }));
  };

  return (
    <form
      className="flex flex-col gap-6"
      onSubmit={(event) => {
        event.preventDefault();
        void submit.run({ lessonId, answers: payloadOf(fields, answers) });
      }}
    >
      <CardContent>
        <FieldGroup>
          {fields.map((field) => {
            const id = `${formId}-${field.key}`;
            const value = answers[field.key];

            if (field.type === "bool" || field.type === "consent") {
              return (
                <Field key={field.key} orientation="horizontal">
                  <Checkbox
                    id={id}
                    checked={value?.kind === "check" && value.checked}
                    onCheckedChange={(checked) => {
                      set(field.key, { kind: "check", checked });
                    }}
                  />
                  <FieldLabel htmlFor={id}>{field.label}</FieldLabel>
                </Field>
              );
            }

            if (field.type === "multi") {
              const picked = value?.kind === "picks" ? value.picks : [];

              return (
                <Field key={field.key}>
                  <FieldLabel>{field.label}</FieldLabel>
                  {(field.options ?? []).map((option) => (
                    <Field
                      key={option.value}
                      orientation="horizontal"
                      className="gap-2"
                    >
                      <Checkbox
                        id={`${id}-${option.value}`}
                        checked={picked.includes(option.value)}
                        onCheckedChange={(checked) => {
                          set(field.key, {
                            kind: "picks",
                            picks: checked
                              ? [...picked, option.value]
                              : picked.filter((item) => item !== option.value),
                          });
                        }}
                      />
                      <FieldLabel htmlFor={`${id}-${option.value}`}>
                        {option.label}
                      </FieldLabel>
                    </Field>
                  ))}
                </Field>
              );
            }

            const text = value?.kind === "text" ? value.text : "";

            return (
              <Field key={field.key}>
                <FieldLabel htmlFor={id}>{field.label}</FieldLabel>
                {field.type === "option" || field.type === "nps" ? (
                  <Select
                    value={text === "" ? null : text}
                    items={optionItems(field)}
                    onValueChange={(next) => {
                      set(field.key, { kind: "text", text: next ?? "" });
                    }}
                  >
                    <SelectTrigger id={id} className="w-full">
                      <SelectValue placeholder={t("Pick one")} />
                    </SelectTrigger>
                    <SelectContent>
                      {optionItems(field).map((item) => (
                        <SelectItem key={item.value} value={item.value}>
                          {item.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                ) : field.type === "textarea" || field.type === "json" ? (
                  <Textarea
                    id={id}
                    value={text}
                    required={field.required}
                    onChange={(event) => {
                      set(field.key, {
                        kind: "text",
                        text: event.target.value,
                      });
                    }}
                  />
                ) : (
                  <Input
                    id={id}
                    type={field.type === "integer" ? "number" : field.type}
                    value={text}
                    required={field.required}
                    onChange={(event) => {
                      set(field.key, {
                        kind: "text",
                        text: event.target.value,
                      });
                    }}
                  />
                )}
              </Field>
            );
          })}
        </FieldGroup>
      </CardContent>
      <CardFooter className="flex justify-end">
        <Button type="submit" disabled={submit.pending || fields.length === 0}>
          <SendIcon />
          {t("Submit answers")}
        </Button>
      </CardFooter>
    </form>
  );
}
