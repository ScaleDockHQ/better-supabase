"use client";

import type { ReactElement, ReactNode } from "react";

import {
  type Preset,
  PRESET_FIELDS,
  PRESET_FRAMEWORKS,
  type PresetName,
  type ResolvedPreset,
  withPresetField,
} from "better-supabase/preset";
import { ShuffleIcon, TerminalIcon, TriangleAlertIcon } from "lucide-react";
import { useId } from "react";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { type BlockGroup, packageDir } from "@/lib/create";

import { BlockPicker } from "./block-picker";
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

/** The monorepo option: `dir` is the text in the field, valid or not. */
export interface PackageOption {
  readonly on: boolean;
  readonly dir: string;
}

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
  children: ReactNode;
}): ReactElement {
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
}): ReactElement {
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
      <SelectTrigger id={id} size="sm" className="w-full">
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

function Section({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}): ReactElement {
  return (
    <fieldset className="flex flex-col gap-3">
      <legend className="pb-2 text-sm font-medium">{title}</legend>
      {children}
    </fieldset>
  );
}

/**
 * Every option `/create` has, top to bottom like the shadcn customizer: the
 * preset, the stack, the monorepo package, then conventions, integrations
 * and blocks as collapsible sections, with the code and actions pinned below.
 */
export function OptionsPanel({
  preset,
  resolved,
  named,
  code,
  groups,
  pkg,
  onPreset,
  onNamedPreset,
  onToggleBlock,
  onPackage,
  onShuffle,
  onGetCode,
}: {
  preset: Preset;
  resolved: ResolvedPreset;
  named: PresetName | undefined;
  code: string;
  groups: readonly BlockGroup[];
  pkg: PackageOption;
  onPreset: (update: (current: Preset) => Preset) => void;
  onNamedPreset: (name: PresetName) => void;
  onToggleBlock: (name: string) => void;
  onPackage: (pkg: PackageOption) => void;
  onShuffle: () => void;
  onGetCode: () => void;
}): ReactElement {
  const ids = useId();

  const fieldConflicts = resolved.conflicts.filter(
    (conflict) => conflict.field !== undefined,
  );

  const dirInvalid = pkg.on && packageDir(pkg.dir) === undefined;

  return (
    <form
      aria-label="Preset"
      className="flex h-full min-h-0 flex-col"
      onSubmit={(event) => {
        event.preventDefault();
      }}
    >
      <ScrollArea className="sidebar-scroll min-h-0 flex-1">
        <div className="flex flex-col gap-6 p-4">
          <PresetPicker selected={named} onSelect={onNamedPreset} />

          <Section title="Stack">
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
                    onPreset((current) => ({ ...current, framework }));
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
                size="sm"
                spacing={0}
                className="w-full"
                value={[preset.platforms]}
                onValueChange={(value) => {
                  const platforms = PLATFORMS.find((each) => each === value[0]);

                  if (platforms !== undefined) {
                    onPreset((current) => ({ ...current, platforms }));
                  }
                }}
              >
                {PLATFORMS.map((platform) => (
                  <ToggleGroupItem
                    key={platform}
                    value={platform}
                    className="flex-1"
                  >
                    {PLATFORM_LABELS[platform]}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
            </div>
          </Section>

          <Section title="Monorepo">
            <label
              htmlFor={`${ids}-monorepo`}
              className="flex cursor-pointer items-start justify-between gap-3"
            >
              <span className="flex flex-col gap-0.5">
                <span className="text-sm">Workspace package</span>
                <span className="text-xs text-muted-foreground">
                  The app lives in a package; the SQL stays in the root{" "}
                  <code className="font-mono">supabase/</code>.
                </span>
              </span>
              <Switch
                id={`${ids}-monorepo`}
                checked={pkg.on}
                onCheckedChange={(on) => {
                  onPackage({ ...pkg, on });
                }}
              />
            </label>
            {pkg.on ? (
              <Field id={`${ids}-package`} label="Package directory">
                <Input
                  id={`${ids}-package`}
                  name="package"
                  value={pkg.dir}
                  spellCheck={false}
                  autoComplete="off"
                  aria-invalid={dirInvalid}
                  aria-describedby={
                    dirInvalid ? `${ids}-package-error` : undefined
                  }
                  onChange={(event) => {
                    onPackage({ ...pkg, dir: event.target.value });
                  }}
                  className="font-mono"
                />
                {dirInvalid ? (
                  <p
                    id={`${ids}-package-error`}
                    className="text-xs text-destructive"
                  >
                    Use a path inside the repository, like apps/web, without{" "}
                    <code className="font-mono">..</code>.
                  </p>
                ) : null}
              </Field>
            ) : null}
          </Section>

          <Accordion multiple defaultValue={["blocks"]}>
            <AccordionItem value="conventions">
              <AccordionTrigger>Conventions</AccordionTrigger>
              <AccordionContent className="flex flex-col gap-3">
                {CONVENTION_KEYS.map((key) => (
                  <Field
                    key={key}
                    id={`${ids}-${key}`}
                    label={FIELD_LABELS[key]}
                  >
                    <OptionSelect
                      id={`${ids}-${key}`}
                      value={preset[key]}
                      values={valuesOf(key)}
                      onChange={(value) => {
                        onPreset((current) =>
                          withPresetField(current, key, value),
                        );
                      }}
                    />
                  </Field>
                ))}
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
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="integrations">
              <AccordionTrigger>Integrations</AccordionTrigger>
              <AccordionContent className="flex flex-col gap-1">
                {valuesOf("integrations").map((value) => (
                  <label
                    key={value}
                    className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors hover:bg-muted/60"
                  >
                    <input
                      type="checkbox"
                      name="integration"
                      value={value}
                      checked={preset.integrations.some(
                        (each) => each === value,
                      )}
                      onChange={() => {
                        onPreset((current) =>
                          withPresetField(current, "integrations", value),
                        );
                      }}
                      className="size-4 shrink-0 accent-primary"
                    />
                    {value}
                  </label>
                ))}
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="blocks">
              <AccordionTrigger>
                <span className="flex flex-1 items-baseline justify-between gap-2 pr-2">
                  Blocks
                  <span className="text-xs font-normal text-muted-foreground tabular-nums">
                    {resolved.blocks.length} installed
                  </span>
                </span>
              </AccordionTrigger>
              <AccordionContent>
                <BlockPicker groups={groups} onToggle={onToggleBlock} />
              </AccordionContent>
            </AccordionItem>
          </Accordion>
        </div>
      </ScrollArea>

      <div className="flex flex-col gap-2 border-t border-border bg-background p-4">
        <p className="truncate font-mono text-xs text-muted-foreground">
          preset: {code}
        </p>
        <div className="flex gap-2">
          <Button type="button" variant="outline" size="sm" onClick={onShuffle}>
            <ShuffleIcon aria-hidden="true" />
            Shuffle
          </Button>
          <Button
            type="button"
            size="sm"
            className="flex-1"
            onClick={onGetCode}
          >
            <TerminalIcon aria-hidden="true" />
            Get code
          </Button>
        </div>
      </div>
    </form>
  );
}
