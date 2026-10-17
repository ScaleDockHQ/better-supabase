// #region recipe:settings-layout
"use client";

import type { SettingEntries } from "better-supabase/blocks/settings";
import type {
  SettingField,
  SettingsState,
} from "better-supabase/blocks/settings/react";

import { useSettings } from "better-supabase/blocks/settings/react";
import { tenantOf } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import { toast } from "sonner";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Field,
  FieldContent,
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
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { useAuth } from "@/lib/hooks";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

import { settings } from "../settings-definition";

/** The API schema `gen` wrote for the settings block. */
const API_SCHEMA = blockConfig.settings.api;

/** What a control produces; the key's schema validates it before it is stored. */
type ControlValue = string | number | boolean;

/** The control for one field, picked by the kind its schema declares. */
function SettingControl({
  id,
  field,
  value,
  disabled,
  onChange,
}: {
  id: string;
  field: SettingField;
  value: unknown;
  disabled: boolean;
  onChange: (value: ControlValue) => void;
}) {
  switch (field.kind) {
    case "boolean": {
      return (
        <Switch
          id={id}
          checked={value === true}
          disabled={disabled}
          onCheckedChange={(checked: boolean) => {
            onChange(checked);
          }}
        />
      );
    }

    case "choice": {
      const items = field.choices.map((choice) => ({
        value: String(choice),
        label: String(choice),
      }));

      return (
        <Select
          value={String(value)}
          items={items}
          disabled={disabled}
          onValueChange={(next) => {
            const choice = field.choices.find((each) => String(each) === next);

            if (choice !== undefined) {
              onChange(choice);
            }
          }}
        >
          <SelectTrigger id={id} className="w-48 capitalize">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {items.map((item) => (
              <SelectItem
                key={item.value}
                value={item.value}
                className="capitalize"
              >
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      );
    }

    case "number":
    case "text":
    case "json": {
      return (
        <Input
          id={id}
          className="w-48"
          type={field.kind === "number" ? "number" : "text"}
          defaultValue={field.kind === "json" ? "" : String(value ?? "")}
          disabled={disabled || field.kind === "json"}
          onBlur={(event) => {
            const next = event.currentTarget.value;
            onChange(field.kind === "number" ? Number(next) : next);
          }}
        />
      );
    }

    default: {
      const unknown: never = field.kind;

      return unknown;
    }
  }
}

/** One scope of the definition as a card: a row per key, saved on change. */
function SettingsSection<E extends SettingEntries>({
  title,
  description,
  editable,
  state,
}: {
  title: string;
  description: string;
  editable: boolean;
  state: SettingsState<E>;
}) {
  const t = useExtracted("settings");
  const errorMessage = useErrorMessage();
  const baseId = useId();

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        {state.values === undefined ? (
          <Skeleton className="h-16" aria-busy="true" />
        ) : (
          <FieldGroup>
            {state.fields.map((field) => (
              <Field key={field.key} orientation="horizontal">
                <FieldContent>
                  <FieldLabel htmlFor={`${baseId}-${field.key}`}>
                    {field.title ?? field.key}
                  </FieldLabel>
                  {field.description ? (
                    <FieldDescription>{field.description}</FieldDescription>
                  ) : null}
                  {editable ? null : (
                    <FieldDescription>
                      {t("Only admins can change this.")}
                    </FieldDescription>
                  )}
                </FieldContent>
                <SettingControl
                  id={`${baseId}-${field.key}`}
                  field={field}
                  value={state.values?.[field.key]}
                  disabled={!editable || state.saving === field.key}
                  onChange={(value) => {
                    void state.setField(field.key, value).then((saved) => {
                      if (!saved.ok) {
                        toast.error(errorMessage(saved.error));
                      }
                    });
                  }}
                />
              </Field>
            ))}
          </FieldGroup>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * The preferences page, generated from `settings-definition.ts`: a card per
 * scope and a control per key, each saved through the settings module.
 */
export function SettingsLayout({
  canEditOrganization,
}: {
  canEditOrganization: boolean;
}) {
  const t = useExtracted("settings");
  const organizationId = tenantOf(useAuth()) ?? null;
  const user = useSettings(settings, { scope: "user", schema: API_SCHEMA });

  const organization = useSettings(settings, {
    scope: "organization",
    organizationId,
    schema: API_SCHEMA,
  });

  return (
    <div className="space-y-6" data-testid="settings-layout">
      <SettingsSection
        title={t("Your preferences")}
        description={t("Only you see these.")}
        editable
        state={user}
      />
      {organizationId ? (
        <SettingsSection
          title={t("Organization defaults")}
          description={t("Shared by everyone in the organization.")}
          editable={canEditOrganization}
          state={organization}
        />
      ) : null}
    </div>
  );
}
// #endregion recipe:settings-layout
