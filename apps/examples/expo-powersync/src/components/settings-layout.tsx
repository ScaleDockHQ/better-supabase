// #region recipe:settings-layout
import type { SettingEntries } from "better-supabase/blocks/settings";
import type {
  SettingField,
  SettingsState,
} from "better-supabase/blocks/settings/react";

import { useSettings } from "better-supabase/blocks/settings/react";
import { tenantOf, useAuth } from "better-supabase/react";
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  Switch,
  Text,
  TextInput,
  View,
} from "react-native";

import { API_SCHEMA } from "../lib/blocks";
import { settings } from "../lib/settings";

/** What a control produces; the key's schema validates it before it is stored. */
type ControlValue = string | number | boolean;

/** The control for one field, picked by the kind its schema declares. */
function SettingControl({
  field,
  value,
  disabled,
  onChange,
}: {
  readonly field: SettingField;
  readonly value: unknown;
  readonly disabled: boolean;
  readonly onChange: (value: ControlValue) => void;
}) {
  switch (field.kind) {
    case "boolean":
      return (
        <Switch
          value={value === true}
          disabled={disabled}
          onValueChange={onChange}
        />
      );
    case "choice":
      return (
        <View style={{ flexDirection: "row", gap: 6 }}>
          {field.choices.map((choice) => (
            <Pressable
              key={String(choice)}
              accessibilityRole="radio"
              accessibilityState={{ checked: choice === value, disabled }}
              disabled={disabled}
              onPress={() => {
                onChange(choice);
              }}
              style={{
                paddingHorizontal: 10,
                paddingVertical: 6,
                borderWidth: 1,
                borderRadius: 8,
                borderColor: choice === value ? "#111" : "#e5e5e5",
              }}
            >
              <Text>{String(choice)}</Text>
            </Pressable>
          ))}
        </View>
      );
    case "number":
    case "text":
    case "json":
      return (
        <TextInput
          defaultValue={field.kind === "json" ? "" : String(value ?? "")}
          editable={!disabled && field.kind !== "json"}
          keyboardType={field.kind === "number" ? "numeric" : "default"}
          onEndEditing={(event) => {
            const next = event.nativeEvent.text;
            onChange(field.kind === "number" ? Number(next) : next);
          }}
          style={{ minWidth: 120, borderWidth: 1, borderRadius: 8, padding: 6 }}
        />
      );
    default: {
      const unknown: never = field.kind;
      return unknown;
    }
  }
}

/** One scope of the definition: a row per key, saved on change. */
function SettingsSection<E extends SettingEntries>({
  title,
  state,
}: {
  readonly title: string;
  readonly state: SettingsState<E>;
}) {
  if (state.values === undefined) return <ActivityIndicator />;
  return (
    <View style={{ gap: 12 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>{title}</Text>
      {state.fields.map((field) => (
        <View key={field.key} style={{ flexDirection: "row", gap: 12 }}>
          <View style={{ flex: 1 }}>
            <Text>{field.title ?? field.key}</Text>
            {field.description ? (
              <Text style={{ color: "#737373" }}>{field.description}</Text>
            ) : null}
          </View>
          <SettingControl
            field={field}
            value={state.values?.[field.key]}
            disabled={state.saving === field.key}
            onChange={(value) => void state.setField(field.key, value)}
          />
        </View>
      ))}
      {state.error ? (
        <Text style={{ color: "#b91c1c" }}>{state.error.message}</Text>
      ) : null}
    </View>
  );
}

/** The preferences screen, generated from the settings definition. */
export function SettingsLayout() {
  const organizationId = tenantOf(useAuth()) ?? null;
  const user = useSettings(settings, { scope: "user", schema: API_SCHEMA });
  const organization = useSettings(settings, {
    scope: "organization",
    organizationId,
    schema: API_SCHEMA,
  });
  return (
    <ScrollView contentContainerStyle={{ gap: 24, padding: 16 }}>
      <SettingsSection title="Your preferences" state={user} />
      {organizationId ? (
        <SettingsSection title="Organization defaults" state={organization} />
      ) : null}
    </ScrollView>
  );
}
// #endregion recipe:settings-layout
