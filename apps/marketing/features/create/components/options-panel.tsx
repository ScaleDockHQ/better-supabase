"use client";

import type { ReactElement, ReactNode } from "react";

import {
  type Preset,
  PRESET_FIELDS,
  PRESET_FRAMEWORKS,
  type PresetName,
  type PresetPlatforms,
  PRESETS,
  type ResolvedPreset,
  withPresetField,
} from "better-supabase/preset";
import {
  ChevronDownIcon,
  ShuffleIcon,
  TerminalIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { useId, useState } from "react";
import { siSupabase } from "simple-icons";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { BrandLogo } from "@/components/site/brand-icons";
import { CopyButton } from "@/components/site/copy-button";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
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
import {
  AUTH_CHOICE_INFO,
  AUTH_CHOICES,
  type AuthChoice,
  CONVENTION_KEYS,
  CUSTOM_PRESET,
  CONVENTION_VALUES,
  FIELD_LABELS,
  fieldLabel,
  FRAMEWORKS,
  impliedIntegrations,
  impliedNote,
  INTEGRATION_ORDER,
  INTEGRATIONS,
  type OptionInfo,
  PLATFORM_LABELS,
  PLATFORMS,
  platformUnavailable,
  withFramework,
} from "@/lib/create-options";
import { cn } from "@/lib/utils";

import { BlockPicker } from "./block-picker";
import { useCanvasBridge } from "./canvas-bridge";
import { PresetPicker } from "./preset-picker";
import { PrimitivePicker } from "./primitive-picker";

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
  hint,
  children,
}: {
  id: string;
  label: string;
  hint?: string | undefined;
  children: ReactNode;
}): ReactElement {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-xs text-muted-foreground">
        {label}
      </label>
      {children}
      {hint === undefined ? null : (
        <p id={`${id}-hint`} className="text-xs text-muted-foreground">
          {hint}
        </p>
      )}
    </div>
  );
}

function OptionSelect({
  id,
  value,
  options,
  describedBy,
  onChange,
}: {
  id: string;
  value: string;
  options: Readonly<Record<string, OptionInfo>>;
  describedBy?: string | undefined;
  onChange: (value: string) => void;
}): ReactElement {
  const entries = Object.entries(options);

  return (
    <Select
      value={value}
      items={entries.map(([each, info]) => ({
        value: each,
        label: info.label,
      }))}
      disabled={entries.length < 2}
      onValueChange={(next) => {
        if (next !== null) {
          onChange(next);
        }
      }}
    >
      <SelectTrigger
        id={id}
        size="sm"
        className="w-full"
        aria-describedby={describedBy}
      >
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {entries.map(([each, info]) => (
          <SelectItem key={each} value={each}>
            {info.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function FrameworkLabel({ framework }: { framework: string }): ReactNode {
  const info = Object.entries(FRAMEWORKS).find(
    ([name]) => name === framework,
  )?.[1];

  return info === undefined ? (
    framework
  ) : (
    <>
      <BrandLogo mark={info.mark} className="size-4" />
      {info.label}
    </>
  );
}

function StackSection({
  preset,
  resolved,
  onPreset,
}: {
  preset: Preset;
  resolved: ResolvedPreset;
  onPreset: (update: (current: Preset) => Preset) => void;
}): ReactElement {
  const ids = useId();

  const blocked = PLATFORMS.map((platform) =>
    platformUnavailable(preset.framework, platform),
  ).find((reason) => reason !== undefined);

  const fieldConflicts = resolved.conflicts.filter(
    (conflict) => conflict.field !== undefined,
  );

  const current = platformUnavailable(preset.framework, preset.platforms);

  return (
    <div className="flex flex-col gap-3">
      <Field id={`${ids}-framework`} label={FIELD_LABELS.framework}>
        <Select
          value={preset.framework}
          onValueChange={(value) => {
            const framework = PRESET_FRAMEWORKS.find((each) => each === value);

            if (framework !== undefined) {
              onPreset((current) => withFramework(current, framework));
            }
          }}
        >
          <SelectTrigger id={`${ids}-framework`} size="sm" className="w-full">
            <SelectValue>
              {(value: string) => <FrameworkLabel framework={value} />}
            </SelectValue>
          </SelectTrigger>
          <SelectContent>
            {PRESET_FRAMEWORKS.map((framework) => (
              <SelectItem key={framework} value={framework}>
                <FrameworkLabel framework={framework} />
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
      <div className="flex flex-col gap-1.5">
        <p id={`${ids}-platforms`} className="text-xs text-muted-foreground">
          {FIELD_LABELS.platforms}
        </p>
        <ToggleGroup
          aria-labelledby={`${ids}-platforms`}
          aria-describedby={
            blocked === undefined ? undefined : `${ids}-platforms-note`
          }
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
          {PLATFORMS.map((platform) => {
            const reason = platformUnavailable(preset.framework, platform);

            return (
              <ToggleGroupItem
                key={platform}
                value={platform}
                disabled={reason !== undefined}
                title={reason}
                className="flex-1"
              >
                {PLATFORM_TOGGLE_LABELS[platform]}
              </ToggleGroupItem>
            );
          })}
        </ToggleGroup>
        {blocked === undefined ? null : (
          <p
            id={`${ids}-platforms-note`}
            className="text-xs text-muted-foreground"
          >
            {blocked}
          </p>
        )}
      </div>
      {fieldConflicts.length > 0 ? (
        <Alert variant="warning">
          <TriangleAlertIcon aria-hidden="true" />
          <AlertTitle>These choices conflict</AlertTitle>
          <AlertDescription>
            <ul className="flex flex-col gap-1">
              {fieldConflicts.map((conflict) => (
                <li key={conflict.field}>
                  {fieldLabel(conflict.field ?? "")}:{" "}
                  {current ?? conflict.reason}
                </li>
              ))}
            </ul>
          </AlertDescription>
        </Alert>
      ) : null}
    </div>
  );
}

function AuthSection({
  choice,
  onChoice,
}: {
  choice: AuthChoice;
  onChoice: (choice: AuthChoice) => void;
}): ReactElement {
  const ids = useId();

  return (
    <div className="flex flex-col">
      <p id={`${ids}-auth`} className="sr-only">
        {FIELD_LABELS.access}
      </p>
      <RadioGroup
        aria-labelledby={`${ids}-auth`}
        value={choice}
        className="gap-1"
        onValueChange={(value) => {
          const next = AUTH_CHOICES.find((each) => each === value);

          if (next !== undefined) {
            onChoice(next);
          }
        }}
      >
        {AUTH_CHOICES.map((each) => {
          const info = AUTH_CHOICE_INFO[each];

          return (
            <label
              key={each}
              htmlFor={`${ids}-${each}`}
              className="flex cursor-pointer items-start gap-2 rounded-md px-2 py-1.5 transition-colors hover:bg-muted/60"
            >
              <RadioGroupItem
                id={`${ids}-${each}`}
                value={each}
                aria-describedby={`${ids}-${each}-hint`}
                className="mt-0.5"
              />
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="flex items-center gap-2 text-sm">
                  {info.label}
                  {"optional" in info ? (
                    <Badge variant="outline">Optional</Badge>
                  ) : null}
                </span>
                <span
                  id={`${ids}-${each}-hint`}
                  className="text-xs text-muted-foreground"
                >
                  {info.hint}
                </span>
              </span>
            </label>
          );
        })}
      </RadioGroup>
    </div>
  );
}

function IntegrationRows({
  preset,
  onPreset,
}: {
  preset: Preset;
  onPreset: (update: (current: Preset) => Preset) => void;
}): ReactElement {
  const ids = useId();
  const implied = impliedIntegrations(preset.framework);

  return (
    <div className="flex flex-col gap-2">
      <p className="text-xs text-muted-foreground">
        Glue files <code className="font-mono">better-supabase init</code>{" "}
        writes into your app.
      </p>
      <div className="flex flex-col gap-1">
        {INTEGRATION_ORDER.map((name) => {
          const info = INTEGRATIONS[name];
          const reason = implied.get(name);
          const locked = reason !== undefined;
          const checked = locked || preset.integrations.includes(name);
          const describedBy = `${ids}-${name}-about`;

          return (
            <label
              key={name}
              htmlFor={`${ids}-${name}`}
              className={cn(
                "flex items-start gap-3 rounded-md px-2 py-2 transition-colors",
                locked
                  ? "cursor-not-allowed"
                  : "cursor-pointer hover:bg-muted/60",
              )}
            >
              <Checkbox
                id={`${ids}-${name}`}
                name="integration"
                value={name}
                checked={checked}
                disabled={locked}
                aria-describedby={describedBy}
                onCheckedChange={() => {
                  onPreset((current) =>
                    withPresetField(current, "integrations", name),
                  );
                }}
                className="mt-0.5"
              />
              <BrandLogo mark={info.mark} className="mt-0.5 size-4" />
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="text-sm font-medium">{info.title}</span>
                <span
                  id={describedBy}
                  className="flex flex-col gap-0.5 text-xs text-muted-foreground"
                >
                  <span>{info.description}</span>
                  <span className="flex flex-wrap gap-x-2 font-mono">
                    {info.files.map((file) => (
                      <span key={file} className="break-words">
                        {file}
                      </span>
                    ))}
                  </span>
                  {locked ? (
                    <span>{impliedNote(reason, preset.framework)}</span>
                  ) : null}
                </span>
              </span>
            </label>
          );
        })}
      </div>
    </div>
  );
}

const GROUP_CONTENT = "px-2 pt-3";

/** Shorter than `PLATFORM_LABELS` so three toggles fit the sidebar. */
const PLATFORM_TOGGLE_LABELS = {
  web: "Web",
  native: "Native",
  both: "Both",
} satisfies Readonly<Record<PresetPlatforms, string>>;

function GroupTrigger({
  title,
  summary,
}: {
  title: string;
  summary: ReactNode;
}): ReactElement {
  return (
    <AccordionTrigger className="items-center gap-2 px-2 py-3 transition-colors hover:bg-muted/50 hover:no-underline aria-expanded:bg-muted/50 aria-expanded:hover:bg-muted *:data-[slot=accordion-trigger-icon]:hidden">
      <span className="flex min-w-0 flex-1 items-baseline justify-between gap-2">
        {title}
        <span className="truncate text-xs font-normal text-muted-foreground tabular-nums">
          {summary}
        </span>
      </span>
      <ChevronDownIcon
        aria-hidden="true"
        className="pointer-events-none size-4 shrink-0 text-muted-foreground transition-transform duration-200 group-aria-expanded/accordion-trigger:rotate-180 motion-reduce:transition-none"
      />
    </AccordionTrigger>
  );
}

function stackSummary(preset: Preset): string {
  const framework =
    Object.entries(FRAMEWORKS).find(([name]) => name === preset.framework)?.[1]
      .label ?? preset.framework;

  return `${framework}, ${PLATFORM_LABELS[preset.platforms].toLowerCase()}`;
}

function integrationCount(preset: Preset): number {
  const on = new Set<string>(preset.integrations);

  for (const name of impliedIntegrations(preset.framework).keys()) {
    on.add(name);
  }

  return on.size;
}

/**
 * Every option `/create` has, top to bottom like the shadcn customizer: the
 * preset, the stack, auth and permissions, conventions, integrations and
 * primitives and blocks as collapsible sections whose triggers show the
 * current value, with the code and actions pinned below. Only the preset
 * starts open; the blocks open when the canvas asks to show one.
 */
export function OptionsPanel({
  preset,
  resolved,
  named,
  code,
  groups,
  pkg,
  authChoice,
  onPreset,
  onAuthChoice,
  onNamedPreset,
  onToggleBlock,
  onPackage,
  aiPrompt,
  onShuffle,
  onGetCode,
  onDeploy,
}: {
  preset: Preset;
  resolved: ResolvedPreset;
  named: PresetName | undefined;
  code: string;
  groups: readonly BlockGroup[];
  pkg: PackageOption;
  authChoice: AuthChoice;
  onPreset: (update: (current: Preset) => Preset) => void;
  onAuthChoice: (choice: AuthChoice) => void;
  onNamedPreset: (name: PresetName) => void;
  onToggleBlock: (name: string) => void;
  onPackage: (pkg: PackageOption) => void;
  /** The AI instructions for the current choices, copied from the footer. */
  aiPrompt: string;
  onShuffle: () => void;
  onGetCode: () => void;
  /** Opens the deploy dialog; without it, deploying is turned off. */
  onDeploy?: (() => void) | undefined;
}): ReactElement {
  const ids = useId();
  const { state: bridge } = useCanvasBridge();
  const [sections, setSections] = useState<readonly string[]>(["preset"]);
  const [revealed, setRevealed] = useState(bridge.reveal);

  if (bridge.reveal !== revealed) {
    setRevealed(bridge.reveal);

    if (bridge.reveal !== null && !sections.includes("blocks")) {
      setSections([...sections, "blocks"]);
    }
  }

  const dirInvalid = pkg.on && packageDir(pkg.dir) === undefined;

  const stackConflicts = resolved.conflicts.filter(
    (conflict) => conflict.field !== undefined,
  ).length;

  return (
    <form
      aria-label="Preset"
      className="flex h-full min-h-0 flex-col"
      onSubmit={(event) => {
        event.preventDefault();
      }}
    >
      <ScrollArea className="sidebar-scroll min-h-0 flex-1">
        <div className="flex flex-col p-2">
          <Accordion
            multiple
            value={[...sections]}
            onValueChange={(value) => {
              setSections(value.map(String));
            }}
          >
            <AccordionItem value="preset">
              <GroupTrigger
                title="Preset"
                summary={
                  named === undefined
                    ? CUSTOM_PRESET.label
                    : PRESETS[named].title
                }
              />
              <AccordionContent className={GROUP_CONTENT}>
                <PresetPicker selected={named} onSelect={onNamedPreset} />
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="stack">
              <GroupTrigger
                title="Stack"
                summary={
                  stackConflicts > 0 ? (
                    <Badge variant="warning-light">Conflict</Badge>
                  ) : (
                    stackSummary(preset)
                  )
                }
              />
              <AccordionContent className={GROUP_CONTENT}>
                <StackSection
                  preset={preset}
                  resolved={resolved}
                  onPreset={onPreset}
                />
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="auth">
              <GroupTrigger
                title={FIELD_LABELS.access}
                summary={AUTH_CHOICE_INFO[authChoice].label}
              />
              <AccordionContent className={GROUP_CONTENT}>
                <AuthSection choice={authChoice} onChoice={onAuthChoice} />
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="conventions">
              <GroupTrigger
                title="Conventions"
                summary={`${preset.casing}, ${preset.idType}`}
              />
              <AccordionContent
                className={cn(GROUP_CONTENT, "flex flex-col gap-3")}
              >
                {CONVENTION_KEYS.map((key) => {
                  const options: Readonly<Record<string, OptionInfo>> =
                    CONVENTION_VALUES[key];

                  const hint = Object.entries(options).find(
                    ([value]) => value === preset[key],
                  )?.[1].hint;

                  return (
                    <Field
                      key={key}
                      id={`${ids}-${key}`}
                      label={FIELD_LABELS[key]}
                      hint={hint}
                    >
                      <OptionSelect
                        id={`${ids}-${key}`}
                        value={preset[key]}
                        options={Object.fromEntries(
                          valuesOf(key).map((value) => [
                            value,
                            options[value] ?? { label: value },
                          ]),
                        )}
                        describedBy={
                          hint === undefined ? undefined : `${ids}-${key}-hint`
                        }
                        onChange={(value) => {
                          onPreset((current) =>
                            withPresetField(current, key, value),
                          );
                        }}
                      />
                    </Field>
                  );
                })}
                <p className="text-xs leading-5 text-muted-foreground">
                  Other tenant names arrive with naming conventions.
                </p>
                <label
                  htmlFor={`${ids}-monorepo`}
                  className="flex cursor-pointer items-start justify-between gap-3"
                >
                  <span className="flex flex-col gap-0.5">
                    <span className="text-sm">Monorepo package</span>
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
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="integrations">
              <GroupTrigger
                title="Integrations"
                summary={`${integrationCount(preset)} on`}
              />
              <AccordionContent className={GROUP_CONTENT}>
                <IntegrationRows preset={preset} onPreset={onPreset} />
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="primitives">
              <GroupTrigger title="Primitives" summary="Table, lookup" />
              <AccordionContent className={GROUP_CONTENT}>
                <PrimitivePicker />
              </AccordionContent>
            </AccordionItem>
            <AccordionItem value="blocks">
              <GroupTrigger
                title="Blocks"
                summary={`${resolved.blocks.length} installed`}
              />
              <AccordionContent className={GROUP_CONTENT}>
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
        {onDeploy === undefined ? null : (
          <Button type="button" variant="outline" size="sm" onClick={onDeploy}>
            <BrandLogo mark={siSupabase} className="size-4" />
            Deploy to Supabase
          </Button>
        )}
        <div className="flex gap-2">
          <Button type="button" variant="outline" size="sm" onClick={onShuffle}>
            <ShuffleIcon aria-hidden="true" />
            Shuffle
          </Button>
          <CopyButton
            text={aiPrompt}
            label="Copy AI instructions"
            variant="outline"
            size="sm"
          >
            AI
          </CopyButton>
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
