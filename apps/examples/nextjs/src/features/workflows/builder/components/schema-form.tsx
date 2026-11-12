"use client";

import type { WorkflowStepInfo } from "better-supabase/blocks/workflow-editor";

import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import * as v from "valibot";

import { Checkbox } from "@/components/ui/checkbox";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import {
  InputGroup,
  InputGroupAddon,
  InputGroupInput,
  InputGroupTextarea,
} from "@/components/ui/input-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";

import type { JsonObject, JsonValue } from "../config-templates";
import type { PickerGroup } from "../editor-model";

import { JsonSchema } from "../config-templates";
import { DataPicker } from "./data-picker";

const Scalar = v.union([v.string(), v.number(), v.boolean(), v.null()]);

const PropertySchema = v.object({
  type: v.optional(v.string()),
  title: v.optional(v.string()),
  description: v.optional(v.string()),
  enum: v.optional(v.array(v.string())),
  default: v.optional(JsonSchema),
  minimum: v.optional(v.number()),
  maximum: v.optional(v.number()),
  maxLength: v.optional(v.number()),
  pattern: v.optional(v.string()),
  "x-field": v.optional(v.string()),
  "x-multiline": v.optional(v.boolean()),
  "x-mono": v.optional(v.boolean()),
  "x-scalar": v.optional(v.boolean()),
});

type FieldSchema = v.InferOutput<typeof PropertySchema>;

const Properties = v.record(v.string(), PropertySchema);

/**
 * A scalar the way a condition reads it: `3`, `true` and `"pro"` parse,
 * anything else stays text.
 */
function scalarOf(raw: string): v.InferOutput<typeof Scalar> {
  try {
    const parsed = v.safeParse(Scalar, JSON.parse(raw));

    return parsed.success ? parsed.output : raw;
  } catch {
    return raw;
  }
}

function shown(value: JsonValue | undefined): string {
  if (v.is(v.string(), value)) {
    return value;
  }

  return value === undefined || value === null ? "" : JSON.stringify(value);
}

export interface SchemaFormContext {
  readonly steps: readonly WorkflowStepInfo[];
  readonly definitions: readonly {
    readonly id: string;
    readonly name: string;
  }[];
  readonly credentials: readonly {
    readonly id: string;
    readonly kind: string;
    readonly name: string;
  }[];
  readonly credentialKind: string | undefined;
  readonly groups: readonly PickerGroup[];
}

/** A JSON object as text, parsed when the field loses focus. */
function JsonField({
  id,
  label,
  value,
  onChange,
}: {
  id: string;
  label: string;
  value: JsonValue | undefined;
  onChange: (value: JsonValue | undefined) => void;
}) {
  const t = useExtracted("workflows");

  const [text, setText] = useState(
    value === undefined ? "" : JSON.stringify(value, null, 2),
  );

  const [invalid, setInvalid] = useState(false);

  return (
    <Field data-invalid={invalid}>
      <FieldLabel htmlFor={id}>{label}</FieldLabel>
      <Textarea
        id={id}
        value={text}
        rows={4}
        className="font-mono text-xs"
        aria-invalid={invalid}
        onChange={(event) => {
          setText(event.target.value);
        }}
        onBlur={() => {
          if (text.trim() === "") {
            setInvalid(false);
            onChange(undefined);

            return;
          }

          try {
            const parsed = v.safeParse(JsonSchema, JSON.parse(text));

            setInvalid(!parsed.success);

            if (parsed.success) {
              onChange(parsed.output);
            }
          } catch {
            setInvalid(true);
          }
        }}
      />
      {invalid ? <FieldError>{t("This is not valid JSON")}</FieldError> : null}
    </Field>
  );
}

/**
 * A form for one node's config, generated from the JSON Schema of its kind or
 * step. It reads `enum`, `type`, `default`, `required` and the `x-field`,
 * `x-multiline`, `x-mono` and `x-scalar` hints; text fields get a data picker.
 */
export function SchemaForm({
  schema,
  config,
  context,
  required,
  onChange,
}: {
  schema: JsonObject;
  config: JsonObject;
  context: SchemaFormContext;
  required: readonly string[];
  onChange: (key: string, value: JsonValue | undefined) => void;
}) {
  const t = useExtracted("workflows");
  const id = useId();
  const properties = v.safeParse(Properties, schema["properties"]);

  if (!properties.success) {
    return null;
  }

  const entries = Object.entries(properties.output);

  if (entries.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("This node has no settings.")}
      </p>
    );
  }

  return (
    <FieldGroup>
      {entries.map(([key, field]) => {
        const fieldId = `${id}-${key}`;
        const label = `${field.title ?? key}${required.includes(key) ? " *" : ""}`;
        const value = config[key];

        const input = renderField({
          key,
          field,
          fieldId,
          label,
          value,
          context,
          set: (next) => {
            onChange(key, next);
          },
          t,
        });

        return <div key={key}>{input}</div>;
      })}
    </FieldGroup>
  );
}

function renderField({
  key,
  field,
  fieldId,
  label,
  value,
  context,
  set,
  t,
}: {
  key: string;
  field: FieldSchema;
  fieldId: string;
  label: string;
  value: JsonValue | undefined;
  context: SchemaFormContext;
  set: (value: JsonValue | undefined) => void;
  t: ReturnType<typeof useExtracted>;
}) {
  const hint = field.description;

  const picker = (
    <DataPicker
      groups={context.groups}
      label={field.title ?? key}
      onPick={(marker) => {
        set(`${shown(value)}${marker}`);
      }}
    />
  );

  if (field["x-field"] === "step") {
    return (
      <Field>
        <FieldLabel htmlFor={fieldId}>{label}</FieldLabel>
        <Select
          value={shown(value) || null}
          onValueChange={(next) => {
            set(next ?? "");
          }}
          items={context.steps.map((step) => ({
            value: step.name,
            label: step.title,
          }))}
        >
          <SelectTrigger id={fieldId}>
            <SelectValue placeholder={t("Pick a step")} />
          </SelectTrigger>
          <SelectContent>
            {context.steps.map((step) => (
              <SelectItem key={step.name} value={step.name}>
                {step.title}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
    );
  }

  if (field["x-field"] === "steps") {
    const chosen = v.parse(v.fallback(v.array(v.string()), []), value);

    return (
      <Field>
        <FieldLabel>{label}</FieldLabel>
        <div className="flex flex-col gap-2">
          {context.steps.map((step) => (
            <label key={step.name} className="flex items-center gap-2 text-sm">
              <Checkbox
                checked={chosen.includes(step.name)}
                onCheckedChange={(checked) => {
                  set(
                    checked
                      ? [...chosen, step.name]
                      : chosen.filter((name) => name !== step.name),
                  );
                }}
              />
              {step.title}
            </label>
          ))}
        </div>
      </Field>
    );
  }

  if (field["x-field"] === "definition") {
    return (
      <Field>
        <FieldLabel htmlFor={fieldId}>{label}</FieldLabel>
        <Select
          value={shown(value) || null}
          onValueChange={(next) => {
            set(next ?? "");
          }}
          items={context.definitions.map((definition) => ({
            value: definition.id,
            label: definition.name,
          }))}
        >
          <SelectTrigger id={fieldId}>
            <SelectValue placeholder={t("Pick a workflow")} />
          </SelectTrigger>
          <SelectContent>
            {context.definitions.map((definition) => (
              <SelectItem key={definition.id} value={definition.id}>
                {definition.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <FieldDescription>
          {t("Its published version starts when this node runs.")}
        </FieldDescription>
      </Field>
    );
  }

  if (key === "credential" && context.credentialKind !== undefined) {
    const options = context.credentials.filter(
      (credential) => credential.kind === context.credentialKind,
    );

    return (
      <Field>
        <FieldLabel htmlFor={fieldId}>{label}</FieldLabel>
        <Select
          value={shown(value) || null}
          onValueChange={(next) => {
            set(next ?? "");
          }}
          items={options.map((credential) => ({
            value: credential.id,
            label: credential.name,
          }))}
        >
          <SelectTrigger id={fieldId}>
            <SelectValue placeholder={t("Pick a credential")} />
          </SelectTrigger>
          <SelectContent>
            {options.map((credential) => (
              <SelectItem key={credential.id} value={credential.id}>
                {credential.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
    );
  }

  if (field.enum !== undefined) {
    const options = field.enum;

    return (
      <Field>
        <FieldLabel htmlFor={fieldId}>{label}</FieldLabel>
        <Select
          value={shown(value) || shown(field.default) || null}
          onValueChange={(next) => {
            set(next ?? "");
          }}
          items={options.map((option) => ({ value: option, label: option }))}
        >
          <SelectTrigger id={fieldId}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {options.map((option) => (
              <SelectItem key={option} value={option}>
                {option}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
    );
  }

  if (field.type === "boolean") {
    return (
      <Field orientation="horizontal">
        <Switch
          id={fieldId}
          checked={value === true}
          onCheckedChange={(checked) => {
            set(checked);
          }}
        />
        <FieldLabel htmlFor={fieldId}>{label}</FieldLabel>
      </Field>
    );
  }

  if (field.type === "integer" || field.type === "number") {
    return (
      <Field>
        <FieldLabel htmlFor={fieldId}>{label}</FieldLabel>
        <InputGroup>
          <InputGroupInput
            id={fieldId}
            type="number"
            value={v.is(v.number(), value) ? value : ""}
            min={field.minimum}
            max={field.maximum}
            onChange={(event) => {
              const next = event.target.value;
              set(next === "" ? undefined : Number(next));
            }}
          />
        </InputGroup>
        {hint ? <FieldDescription>{hint}</FieldDescription> : null}
      </Field>
    );
  }

  if (field.type === "object" || field.type === "array") {
    return (
      <JsonField id={fieldId} label={label} value={value} onChange={set} />
    );
  }

  const mono = field["x-mono"] === true ? "font-mono" : undefined;

  return (
    <Field>
      <FieldLabel htmlFor={fieldId}>{label}</FieldLabel>
      <InputGroup>
        {field["x-multiline"] === true ? (
          <InputGroupTextarea
            id={fieldId}
            value={shown(value)}
            rows={4}
            maxLength={field.maxLength}
            className={mono}
            onChange={(event) => {
              set(event.target.value);
            }}
          />
        ) : (
          <InputGroupInput
            id={fieldId}
            value={shown(value)}
            maxLength={field.maxLength}
            className={mono}
            onChange={(event) => {
              set(
                field["x-scalar"] === true
                  ? scalarOf(event.target.value)
                  : event.target.value,
              );
            }}
          />
        )}
        <InputGroupAddon align="inline-end">{picker}</InputGroupAddon>
      </InputGroup>
      {hint ? <FieldDescription>{hint}</FieldDescription> : null}
    </Field>
  );
}
