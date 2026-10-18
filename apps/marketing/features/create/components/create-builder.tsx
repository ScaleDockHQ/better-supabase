"use client";

import {
  encodePreset,
  type Preset,
  PRESET_FIELDS,
  PRESET_FRAMEWORKS,
  presetApplyCommand,
  presetBlocksSource,
  presetConfigSource,
  presetInstallCommand,
  resolvePreset,
  withPresetField,
} from "better-supabase/preset";
import { TriangleAlertIcon } from "lucide-react";
import { useSearchParams } from "next/navigation";
import { useEffect, useId, useMemo, useState } from "react";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import {
  applyNamedPreset,
  blockGroups,
  createHref,
  initialPreset,
  matchingPreset,
  toggleBlock,
} from "@/lib/create";

import { BlockPicker } from "./block-picker";
import { CreateOutput } from "./create-output";
import { PresetPicker } from "./preset-picker";

const CONVENTION_KEYS = [
  "casing",
  "idType",
  "scope",
  "tenantName",
  "access",
  "api",
] as const;

type ConventionKey = (typeof CONVENTION_KEYS)[number];

const FIELD_LABELS = {
  casing: "Casing",
  idType: "Tenant id type",
  scope: "Scope",
  tenantName: "Tenant name",
  access: "Access model",
  api: "API schema",
} satisfies Readonly<Record<ConventionKey, string>>;

const PLATFORMS = ["web", "native", "both"] as const;

const PLATFORM_LABELS = {
  web: "Web",
  native: "Native",
  both: "Both",
} satisfies Readonly<Record<(typeof PLATFORMS)[number], string>>;

function valuesOf(key: string): readonly string[] {
  return PRESET_FIELDS.find((field) => field.key === key)?.values ?? [];
}

function Field({
  id,
  label,
  children,
}: {
  id: string;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-xs text-muted-foreground">
        {label}
      </label>
      {children}
    </div>
  );
}

function OptionSelect({
  id,
  value,
  values,
  onChange,
}: {
  id: string;
  value: string;
  values: readonly string[];
  onChange: (value: string) => void;
}) {
  return (
    <Select
      value={value}
      disabled={values.length < 2}
      onValueChange={(next) => {
        if (next !== null) {
          onChange(next);
        }
      }}
    >
      <SelectTrigger id={id} className="w-full">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {values.map((each) => (
          <SelectItem key={each} value={each}>
            {each}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

export function CreateBuilder() {
  const params = useSearchParams();
  const ids = useId();

  const [preset, setPreset] = useState<Preset>(() =>
    initialPreset(params.get("preset")),
  );

  const resolved = useMemo(() => resolvePreset(preset), [preset]);

  const groups = useMemo(
    () => blockGroups(preset, resolved),
    [preset, resolved],
  );

  const code = encodePreset(preset);
  const named = matchingPreset(preset);

  useEffect(() => {
    const href = createHref(preset);

    if (`${window.location.pathname}${window.location.search}` !== href) {
      window.history.replaceState(null, "", href);
    }
  }, [preset]);

  const fieldConflicts = resolved.conflicts.filter(
    (conflict) => conflict.field !== undefined,
  );

  return (
    <div className="flex flex-col gap-10">
      <PresetPicker
        selected={named}
        onSelect={(name) => {
          setPreset((current) => applyNamedPreset(current, name));
        }}
      />

      <div className="grid grid-cols-1 gap-10 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] xl:items-start">
        <form
          className="flex flex-col gap-8"
          aria-label="Preset"
          onSubmit={(event) => {
            event.preventDefault();
          }}
        >
          <fieldset className="flex flex-col gap-4">
            <legend className="pb-3 text-base font-semibold tracking-tight">
              Stack
            </legend>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Field id={`${ids}-framework`} label="Framework">
                <OptionSelect
                  id={`${ids}-framework`}
                  value={preset.framework}
                  values={PRESET_FRAMEWORKS}
                  onChange={(value) => {
                    const framework = PRESET_FRAMEWORKS.find(
                      (each) => each === value,
                    );

                    if (framework !== undefined) {
                      setPreset((current) => ({ ...current, framework }));
                    }
                  }}
                />
              </Field>
              <div className="flex flex-col gap-1.5">
                <p
                  id={`${ids}-platforms`}
                  className="text-xs text-muted-foreground"
                >
                  Platforms
                </p>
                <ToggleGroup
                  aria-labelledby={`${ids}-platforms`}
                  variant="outline"
                  spacing={0}
                  value={[preset.platforms]}
                  onValueChange={(value) => {
                    const platforms = PLATFORMS.find(
                      (each) => each === value[0],
                    );

                    if (platforms !== undefined) {
                      setPreset((current) => ({ ...current, platforms }));
                    }
                  }}
                >
                  {PLATFORMS.map((platform) => (
                    <ToggleGroupItem key={platform} value={platform}>
                      {PLATFORM_LABELS[platform]}
                    </ToggleGroupItem>
                  ))}
                </ToggleGroup>
              </div>
            </div>
          </fieldset>

          <fieldset className="flex flex-col gap-4">
            <legend className="pb-3 text-base font-semibold tracking-tight">
              Conventions
            </legend>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              {CONVENTION_KEYS.map((key) => (
                <Field key={key} id={`${ids}-${key}`} label={FIELD_LABELS[key]}>
                  <OptionSelect
                    id={`${ids}-${key}`}
                    value={preset[key]}
                    values={valuesOf(key)}
                    onChange={(value) => {
                      setPreset((current) =>
                        withPresetField(current, key, value),
                      );
                    }}
                  />
                </Field>
              ))}
            </div>
            <p className="text-xs leading-5 text-muted-foreground">
              Other tenant names arrive with naming conventions.
            </p>
            {fieldConflicts.length > 0 ? (
              <Alert variant="warning">
                <TriangleAlertIcon aria-hidden="true" />
                <AlertTitle>These choices conflict</AlertTitle>
                <AlertDescription>
                  <ul className="flex flex-col gap-1">
                    {fieldConflicts.map((conflict) => (
                      <li key={conflict.field}>
                        {conflict.field}: {conflict.reason}
                      </li>
                    ))}
                  </ul>
                </AlertDescription>
              </Alert>
            ) : null}
          </fieldset>

          <fieldset className="flex flex-col gap-2">
            <legend className="pb-3 text-base font-semibold tracking-tight">
              Integrations
            </legend>
            <div className="grid grid-cols-1 gap-1 sm:grid-cols-2">
              {valuesOf("integrations").map((value) => (
                <label
                  key={value}
                  className="flex cursor-pointer items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm transition-colors hover:bg-muted/60"
                >
                  <input
                    type="checkbox"
                    name="integration"
                    value={value}
                    checked={preset.integrations.some((each) => each === value)}
                    onChange={() => {
                      setPreset((current) =>
                        withPresetField(current, "integrations", value),
                      );
                    }}
                    className="size-4 shrink-0 accent-primary"
                  />
                  {value}
                </label>
              ))}
            </div>
          </fieldset>

          <BlockPicker
            groups={groups}
            installed={resolved.blocks.length}
            onToggle={(name) => {
              setPreset((current) => toggleBlock(current, name));
            }}
          />
        </form>

        <div className="min-w-0 xl:sticky xl:top-20">
          <CreateOutput
            code={code}
            resolved={resolved}
            installCommand={presetInstallCommand(resolved)}
            applyCommand={presetApplyCommand(resolved)}
            configSource={presetConfigSource(resolved)}
            wiringSource={presetBlocksSource(resolved)}
          />
        </div>
      </div>
    </div>
  );
}
