"use client";

import type { FormField, FormFieldType } from "better-supabase/blocks/forms";

import { useAction } from "better-supabase/react";
import { PlusIcon, SendIcon, Trash2Icon, UploadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Field,
  FieldDescription,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import { publishForm, submitForm } from "../forms-actions";

const BUILDER_TYPES = [
  "text",
  "textarea",
  "email",
  "number",
  "date",
  "bool",
  "option",
] as const satisfies readonly FormFieldType[];

type BuilderType = (typeof BUILDER_TYPES)[number];

interface DraftField {
  /** A React key; never sent. */
  readonly id: string;
  /** Set once published, so later versions keep the answers' keys. */
  readonly key: string | null;
  readonly label: string;
  readonly type: BuilderType;
  readonly required: boolean;
  /** One choice per line, for `option`. */
  readonly choices: string;
}

type Answer =
  | { readonly kind: "text"; readonly text: string }
  | { readonly kind: "check"; readonly checked: boolean };

/** The answers a response sends, by field key. */
type SubmittedAnswers = Readonly<Record<string, string | number | boolean>>;

function isBuilderType(value: unknown): value is BuilderType {
  return BUILDER_TYPES.some((type) => type === value);
}

function draftOf(field: FormField): DraftField {
  return {
    id: crypto.randomUUID(),
    key: field.key,
    label: field.label ?? field.key,
    type: isBuilderType(field.type) ? field.type : "text",
    required: field.required ?? false,
    choices: (field.options ?? []).map((option) => option.label).join("\n"),
  };
}

function choicesOf(field: DraftField): readonly string[] {
  return field.choices
    .split("\n")
    .map((choice) => choice.trim())
    .filter((choice) => choice !== "");
}

/** A camelCase answer key: a letter first, then letters and digits. */
function keyFromLabel(label: string): string {
  const words = label
    .normalize("NFKD")
    .replaceAll(/[^a-zA-Z0-9]+/g, " ")
    .trim()
    .split(" ")
    .filter((word) => word !== "");

  const key = words
    .map((word, index) =>
      index === 0
        ? word.toLowerCase()
        : word[0]?.toUpperCase() + word.slice(1).toLowerCase(),
    )
    .join("")
    .slice(0, 50);

  return /^[a-z]/.test(key) ? key : `field${key}`;
}

/** A field as `publishForm` takes it. */
interface FieldDefinition {
  readonly key: string;
  readonly label: string;
  readonly type: NonNullable<FormField["type"]>;
  readonly required: boolean;
  readonly options?: { value: string; label: string }[];
}

function definitionOf(fields: readonly DraftField[]) {
  const taken = new Set(
    fields.flatMap((field) => (field.key === null ? [] : [field.key])),
  );

  return fields.map((field): FieldDefinition => {
    let key = field.key;

    if (key === null) {
      const base = keyFromLabel(field.label);
      key = base;

      for (let n = 2; taken.has(key); n += 1) {
        key = `${base}${n}`;
      }

      taken.add(key);
    }

    const options = choicesOf(field).map((choice) => ({
      value: choice,
      label: choice,
    }));

    const definition = {
      key,
      label: field.label.trim(),
      type: field.type,
      required: field.required,
    };

    return field.type === "option" ? { ...definition, options } : definition;
  });
}

function sameFields(
  drafts: readonly DraftField[],
  published: readonly FormField[],
): boolean {
  const next = definitionOf(drafts);

  return (
    next.length === published.length &&
    next.every((field, index) => {
      const current = published[index];

      return (
        current !== undefined &&
        field.key === current.key &&
        field.label === (current.label ?? current.key) &&
        field.type === current.type &&
        field.required === (current.required ?? false) &&
        JSON.stringify(field.options ?? []) ===
          JSON.stringify(current.options ?? [])
      );
    })
  );
}

/**
 * The field editor and a live preview of it. The preview submits real answers
 * once the edited fields match the published version.
 */
export function FormBuilderWorkspace({
  formId,
  published,
}: {
  formId: string;
  published: readonly FormField[];
}) {
  const t = useExtracted("forms");
  const errorMessage = useErrorMessage();

  const [fields, setFields] = useState<readonly DraftField[]>(() =>
    published.map(draftOf),
  );

  const publish = useAction(publishForm, {
    onSuccess: ({ number }) => {
      toast.success(t("Version {number, number} published", { number }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const update = (id: string, change: Partial<Omit<DraftField, "id">>) => {
    setFields((current) =>
      current.map((field) =>
        field.id === id ? { ...field, ...change } : field,
      ),
    );
  };

  const labels: Record<BuilderType, string> = {
    text: t("Short text"),
    textarea: t("Long text"),
    email: t("Email"),
    number: t("Number"),
    date: t("Date"),
    bool: t("Yes or no"),
    option: t("Choice"),
  };

  const typeItems = BUILDER_TYPES.map((type) => ({
    value: type,
    label: labels[type],
  }));

  const invalid = fields.some(
    (field) =>
      field.label.trim() === "" ||
      (field.type === "option" && choicesOf(field).length === 0),
  );

  const unchanged = sameFields(fields, published);

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>{t("Fields")}</CardTitle>
          <CardDescription>
            {t("Publishing saves the fields as the form's next version.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {fields.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("Add a field to start building the form.")}
            </p>
          ) : null}
          {fields.map((field, index) => (
            <FieldEditor
              key={field.id}
              field={field}
              position={index + 1}
              typeItems={typeItems}
              onChange={(change) => {
                update(field.id, change);
              }}
              onRemove={() => {
                setFields((current) =>
                  current.filter((other) => other.id !== field.id),
                );
              }}
            />
          ))}
        </CardContent>
        <CardFooter className="flex justify-between gap-2">
          <Button
            variant="outline"
            onClick={() => {
              setFields((current) => [
                ...current,
                {
                  id: crypto.randomUUID(),
                  key: null,
                  label: "",
                  type: "text",
                  required: false,
                  choices: "",
                },
              ]);
            }}
          >
            <PlusIcon />
            {t("Add field")}
          </Button>
          <Button
            disabled={
              publish.pending || fields.length === 0 || invalid || unchanged
            }
            onClick={() => {
              void publish.run({ formId, fields: definitionOf(fields) });
            }}
          >
            <UploadIcon />
            {t("Publish")}
          </Button>
        </CardFooter>
      </Card>
      <FormPreview
        formId={formId}
        fields={definitionOf(fields)}
        canSubmit={unchanged && published.length > 0}
      />
    </div>
  );
}

function FieldEditor({
  field,
  position,
  typeItems,
  onChange,
  onRemove,
}: {
  field: DraftField;
  position: number;
  typeItems: readonly { value: BuilderType; label: string }[];
  onChange: (change: Partial<Omit<DraftField, "id">>) => void;
  onRemove: () => void;
}) {
  const t = useExtracted("forms");
  const fieldId = useId();

  return (
    <div className="flex flex-col gap-3 rounded-lg border p-4">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">
          {t("Field {position, number}", { position })}
        </span>
        <Button
          size="icon-sm"
          variant="ghost"
          aria-label={t("Remove field {position, number}", { position })}
          onClick={onRemove}
        >
          <Trash2Icon />
        </Button>
      </div>
      <FieldGroup className="gap-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <Field>
            <FieldLabel htmlFor={`${fieldId}-label`}>{t("Label")}</FieldLabel>
            <Input
              id={`${fieldId}-label`}
              value={field.label}
              maxLength={200}
              placeholder={t("Your question")}
              aria-invalid={field.label.trim() === "" ? true : undefined}
              onChange={(event) => {
                onChange({ label: event.target.value });
              }}
            />
          </Field>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-type`}>{t("Type")}</FieldLabel>
            <Select
              value={field.type}
              items={typeItems}
              onValueChange={(value) => {
                if (isBuilderType(value)) {
                  onChange({ type: value });
                }
              }}
            >
              <SelectTrigger id={`${fieldId}-type`} className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {typeItems.map((item) => (
                  <SelectItem key={item.value} value={item.value}>
                    {item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
        </div>
        {field.type === "option" ? (
          <Field>
            <FieldLabel htmlFor={`${fieldId}-choices`}>
              {t("Choices")}
            </FieldLabel>
            <Textarea
              id={`${fieldId}-choices`}
              value={field.choices}
              placeholder={t("One choice per line")}
              aria-invalid={choicesOf(field).length === 0 ? true : undefined}
              onChange={(event) => {
                onChange({ choices: event.target.value });
              }}
            />
          </Field>
        ) : null}
        <Field orientation="horizontal">
          <Switch
            id={`${fieldId}-required`}
            checked={field.required}
            onCheckedChange={(required) => {
              onChange({ required });
            }}
          />
          <FieldLabel htmlFor={`${fieldId}-required`}>
            {t("Required")}
          </FieldLabel>
        </Field>
      </FieldGroup>
    </div>
  );
}

function FormPreview({
  formId,
  fields,
  canSubmit,
}: {
  formId: string;
  fields: ReturnType<typeof definitionOf>;
  canSubmit: boolean;
}) {
  const t = useExtracted("forms");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [answers, setAnswers] = useState<Readonly<Record<string, Answer>>>({});

  const submit = useAction(submitForm, {
    onSuccess: () => {
      setAnswers({});
      toast.success(t("Response saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const set = (key: string, value: Answer) => {
    setAnswers((current) => ({ ...current, [key]: value }));
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Preview")}</CardTitle>
        <CardDescription>
          {canSubmit
            ? t("Fill it in to add a response.")
            : t("Publish your changes to submit responses.")}
        </CardDescription>
      </CardHeader>
      <form
        className="flex flex-col gap-6"
        onSubmit={(event) => {
          event.preventDefault();
          void submit.run({ formId, answers: answersOf(fields, answers) });
        }}
      >
        <CardContent>
          {fields.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("The fields you add show up here.")}
            </p>
          ) : (
            <FieldGroup>
              {fields.map((field) => {
                const id = `${fieldId}-${field.key}`;
                const value = answers[field.key];
                const text = value?.kind === "text" ? value.text : "";

                const label =
                  field.label === "" ? t("Untitled field") : field.label;

                if (field.type === "bool") {
                  return (
                    <Field key={field.key} orientation="horizontal">
                      <Checkbox
                        id={id}
                        checked={value?.kind === "check" && value.checked}
                        onCheckedChange={(checked) => {
                          set(field.key, { kind: "check", checked });
                        }}
                      />
                      <FieldLabel htmlFor={id}>{label}</FieldLabel>
                    </Field>
                  );
                }

                return (
                  <Field key={field.key}>
                    <FieldLabel htmlFor={id}>{label}</FieldLabel>
                    {field.type === "textarea" ? (
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
                    ) : field.type === "option" ? (
                      <Select
                        value={text === "" ? null : text}
                        items={(field.options ?? []).map((option) => ({
                          value: option.value,
                          label: option.label,
                        }))}
                        onValueChange={(picked) => {
                          set(field.key, { kind: "text", text: picked ?? "" });
                        }}
                      >
                        <SelectTrigger id={id} className="w-full">
                          <SelectValue placeholder={t("Pick one")} />
                        </SelectTrigger>
                        <SelectContent>
                          {(field.options ?? []).map((option) => (
                            <SelectItem key={option.value} value={option.value}>
                              {option.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    ) : (
                      <Input
                        id={id}
                        type={field.type}
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
                    {field.required ? (
                      <FieldDescription>{t("Required")}</FieldDescription>
                    ) : null}
                  </Field>
                );
              })}
            </FieldGroup>
          )}
        </CardContent>
        <CardFooter className="flex justify-end">
          <Button
            type="submit"
            disabled={!canSubmit || submit.pending || fields.length === 0}
          >
            <SendIcon />
            {t("Submit response")}
          </Button>
        </CardFooter>
      </form>
    </Card>
  );
}

/** Drops empty answers and turns number fields into numbers. */
function answersOf(
  fields: ReturnType<typeof definitionOf>,
  answers: Readonly<Record<string, Answer>>,
): SubmittedAnswers {
  return Object.fromEntries(
    fields.flatMap(
      (field): (readonly [string, string | number | boolean])[] => {
        const value = answers[field.key];

        if (field.type === "bool") {
          return [
            [field.key, value?.kind === "check" && value.checked] as const,
          ];
        }

        if (value?.kind !== "text" || value.text.trim() === "") {
          return [];
        }

        return [
          [
            field.key,
            field.type === "number" ? Number(value.text) : value.text,
          ] as const,
        ];
      },
    ),
  );
}
