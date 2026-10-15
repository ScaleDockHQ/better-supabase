"use client";

import {
  encodePreset,
  type Preset,
  PRESET_FIELDS,
  PRESET_FRAMEWORKS,
  PRESET_NAMES,
  presetBlocksSource,
  presetConfigSource,
  presetInstallCommand,
  type PresetName,
  PRESETS,
  resolvePreset,
  withPresetField,
} from "better-supabase/preset";
import { CheckIcon, CopyIcon, DownloadIcon } from "lucide-react";
import { useSearchParams } from "next/navigation";
import {
  type ReactNode,
  Suspense,
  use,
  useEffect,
  useId,
  useMemo,
  useState,
} from "react";
import * as v from "valibot";

import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  applyNamedPreset,
  blockGroups,
  createHref,
  initialPreset,
  matchingPreset,
  type PresetMigrationFile,
  rowNote,
  toggleBlock,
} from "@/lib/create";

import { PresetGraph } from "./preset-graph";

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

const selectClass =
  "border-input bg-background focus-visible:border-ring focus-visible:ring-ring/50 h-9 w-full rounded-md border px-2.5 text-sm outline-none focus-visible:ring-3 disabled:opacity-50 dark:bg-input/30";

const preClass =
  "border-border bg-card max-h-144 overflow-auto rounded-xl border p-4 font-mono text-code leading-6";

function valuesOf(key: string): readonly string[] {
  return PRESET_FIELDS.find((field) => field.key === key)?.values ?? [];
}

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <Button
      variant="outline"
      size="sm"
      onClick={() => {
        void navigator.clipboard.writeText(text).then(() => {
          setCopied(true);
          setTimeout(() => {
            setCopied(false);
          }, 1500);
        });
      }}
    >
      {copied ? (
        <CheckIcon aria-hidden="true" />
      ) : (
        <CopyIcon aria-hidden="true" />
      )}
      {copied ? "Copied" : label}
    </Button>
  );
}

function CodePanel({
  filename,
  code,
  actions,
}: {
  filename: string;
  code: string;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-muted-foreground font-mono text-xs">{filename}</p>
        <div className="flex gap-2">
          {actions}
          <CopyButton text={code} label="Copy" />
        </div>
      </div>
      <pre className={preClass}>
        <code>{code}</code>
      </pre>
    </div>
  );
}

type MigrationState =
  | { readonly status: "error"; readonly message: string }
  | {
      readonly status: "ready";
      readonly files: readonly PresetMigrationFile[];
    };

const migrationsResponse = v.union([
  v.object({
    files: v.array(
      v.object({ path: v.string(), module: v.string(), contents: v.string() }),
    ),
  }),
  v.object({ error: v.string() }),
]);

async function loadMigrations(code: string): Promise<MigrationState> {
  try {
    const response = await fetch(`/create/migrations?preset=${code}`);
    const body = v.parse(migrationsResponse, await response.json());
    return "error" in body
      ? { status: "error", message: body.error }
      : { status: "ready", files: body.files };
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof Error
          ? error.message
          : "The migrations could not be rendered.",
    };
  }
}

/**
 * One request per code, kept for the session, so `use` gets the same
 * promise on every render and switching back to a selection is instant.
 */
const migrationRequests = new Map<string, Promise<MigrationState>>();

function migrationsFor(code: string): Promise<MigrationState> {
  const known = migrationRequests.get(code);
  if (known !== undefined) return known;
  const request = loadMigrations(code);
  migrationRequests.set(code, request);
  return request;
}

function Migrations({ code }: { code: string }) {
  const state = use(migrationsFor(code));
  if (state.status === "error") {
    return (
      <p className="text-destructive text-sm" role="alert">
        {state.message}
      </p>
    );
  }
  return (
    <div className="flex flex-col gap-3">
      <p className="text-muted-foreground text-sm">
        {state.files.length} files that{" "}
        <code className="text-code font-mono">sql sync</code> writes into{" "}
        <code className="text-code font-mono">supabase/</code>. Turn them into a
        migration with{" "}
        <code className="text-code font-mono">
          supabase db schema declarative sync
        </code>
        .
      </p>
      {state.files.map((file) => (
        <details
          key={file.path}
          className="border-border bg-card rounded-xl border"
        >
          <summary className="cursor-pointer px-4 py-2 font-mono text-xs">
            {file.path}
          </summary>
          <pre className="border-border text-code max-h-96 overflow-auto border-t p-4 font-mono leading-6">
            <code>{file.contents}</code>
          </pre>
        </details>
      ))}
    </div>
  );
}

export function CreateBuilder() {
  const params = useSearchParams();
  const [preset, setPreset] = useState<Preset>(() =>
    initialPreset(params.get("preset")),
  );
  const [tab, setTab] = useState("config");
  const resolved = useMemo(() => resolvePreset(preset), [preset]);
  const groups = useMemo(
    () => blockGroups(preset, resolved),
    [preset, resolved],
  );
  const code = encodePreset(preset);
  const configSource = presetConfigSource(resolved);
  const wiringSource = presetBlocksSource(resolved);
  const command = presetInstallCommand(resolved);
  const named = matchingPreset(preset);
  const ids = useId();

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
    <div className="grid gap-8 lg:grid-cols-3">
      <form
        className="flex flex-col gap-6 lg:col-span-1"
        aria-label="Preset"
        onSubmit={(event) => {
          event.preventDefault();
        }}
      >
        <div className="flex flex-col gap-2">
          <label htmlFor={`${ids}-preset`} className="text-sm font-medium">
            Preset
          </label>
          <select
            id={`${ids}-preset`}
            className={selectClass}
            value={named ?? "custom"}
            onChange={(event) => {
              const value = PRESET_NAMES.find(
                (name) => name === event.target.value,
              );
              if (value !== undefined)
                setPreset(applyNamedPreset(preset, value));
            }}
          >
            {named === undefined && <option value="custom">Custom</option>}
            {PRESET_NAMES.map((name: PresetName) => (
              <option key={name} value={name}>
                {PRESETS[name].title}
              </option>
            ))}
          </select>
          {named !== undefined && (
            <p className="text-muted-foreground text-xs leading-5">
              {PRESETS[named].description}
            </p>
          )}
        </div>

        <fieldset className="flex flex-col gap-3">
          <legend className="mb-2 text-sm font-medium">
            Framework and platforms
          </legend>
          <label htmlFor={`${ids}-framework`} className="sr-only">
            Framework
          </label>
          <select
            id={`${ids}-framework`}
            className={selectClass}
            value={preset.framework}
            onChange={(event) => {
              const value = PRESET_FRAMEWORKS.find(
                (each) => each === event.target.value,
              );
              if (value !== undefined) {
                setPreset((current) => ({ ...current, framework: value }));
              }
            }}
          >
            {PRESET_FRAMEWORKS.map((framework) => (
              <option key={framework} value={framework}>
                {framework}
              </option>
            ))}
          </select>
          <div className="flex gap-4" role="radiogroup" aria-label="Platforms">
            {PLATFORMS.map((platform) => (
              <label key={platform} className="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="platforms"
                  value={platform}
                  checked={preset.platforms === platform}
                  onChange={() => {
                    setPreset((current) => ({
                      ...current,
                      platforms: platform,
                    }));
                  }}
                  className="accent-primary size-4"
                />
                {platform}
              </label>
            ))}
          </div>
        </fieldset>

        <fieldset className="flex flex-col gap-3">
          <legend className="mb-2 text-sm font-medium">Conventions</legend>
          {CONVENTION_KEYS.map((key: ConventionKey) => {
            const values = valuesOf(key);
            return (
              <div key={key} className="flex flex-col gap-1">
                <label
                  htmlFor={`${ids}-${key}`}
                  className="text-muted-foreground text-sm"
                >
                  {FIELD_LABELS[key]}
                </label>
                <select
                  id={`${ids}-${key}`}
                  className={selectClass}
                  value={preset[key]}
                  disabled={values.length < 2}
                  onChange={(event) => {
                    const { value } = event.target;
                    setPreset((current) =>
                      withPresetField(current, key, value),
                    );
                  }}
                >
                  {values.map((value) => (
                    <option key={value} value={value}>
                      {value}
                    </option>
                  ))}
                </select>
              </div>
            );
          })}
          <p className="text-muted-foreground text-xs leading-5">
            Other tenant names arrive with naming conventions.
          </p>
        </fieldset>

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-2 text-sm font-medium">Integrations</legend>
          <div className="grid grid-cols-2 gap-2">
            {valuesOf("integrations").map((value) => (
              <label key={value} className="flex items-center gap-2 text-sm">
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
                  className="accent-primary size-4"
                />
                {value}
              </label>
            ))}
          </div>
        </fieldset>

        <div className="flex flex-col gap-5">
          <p className="text-sm font-medium">
            Blocks{" "}
            <span className="text-muted-foreground font-normal">
              ({resolved.blocks.length} installed)
            </span>
          </p>
          {groups.map((group) => (
            <fieldset key={group.category} className="flex flex-col gap-2">
              <legend className="text-muted-foreground mb-1 text-xs font-semibold tracking-wide uppercase">
                {group.category}
              </legend>
              {group.rows.map((row) => {
                const note = rowNote(row.state);
                const noteId = `${ids}-${row.name}-note`;
                const checked =
                  row.state.kind === "selected" ||
                  row.state.kind === "required";
                return (
                  <label
                    key={row.name}
                    className="flex items-start gap-2.5 text-sm"
                    title={row.description}
                  >
                    <input
                      type="checkbox"
                      name="block"
                      value={row.name}
                      checked={checked}
                      disabled={
                        row.state.kind === "required" ||
                        row.state.kind === "conflict"
                      }
                      aria-describedby={note === undefined ? undefined : noteId}
                      onChange={() => {
                        setPreset((current) => toggleBlock(current, row.name));
                      }}
                      className="accent-primary mt-0.5 size-4 shrink-0"
                    />
                    <span className="flex min-w-0 flex-col">
                      <span className="leading-5">{row.title}</span>
                      {note !== undefined && (
                        <span
                          id={noteId}
                          className="text-muted-foreground text-xs leading-5"
                        >
                          {note}
                        </span>
                      )}
                    </span>
                  </label>
                );
              })}
            </fieldset>
          ))}
        </div>
      </form>

      <div className="flex min-w-0 flex-col gap-6 lg:col-span-2">
        <div className="border-border bg-card flex flex-col gap-3 rounded-xl border p-4">
          <p className="text-sm font-medium">Install</p>
          <p className="text-muted-foreground text-sm leading-6">
            Save the config as{" "}
            <code className="text-code font-mono">
              better-supabase.config.ts
            </code>
            , then add the blocks. The command brings what they require.
          </p>
          <pre className="bg-muted text-code overflow-x-auto rounded-md px-3 py-2 font-mono">
            <code data-testid="install-command">{command}</code>
          </pre>
          <div className="flex flex-wrap gap-2">
            <CopyButton
              text={`${configSource}\n${command}\n`}
              label="Copy config and command"
            />
            <CopyButton text={command} label="Copy command" />
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                const url = URL.createObjectURL(
                  new Blob([configSource], { type: "text/typescript" }),
                );
                const link = document.createElement("a");
                link.href = url;
                link.download = "better-supabase.config.ts";
                link.click();
                URL.revokeObjectURL(url);
              }}
            >
              <DownloadIcon aria-hidden="true" />
              Download config
            </Button>
          </div>
          <p className="text-muted-foreground font-mono text-xs break-all">
            preset: {code}
          </p>
        </div>

        {fieldConflicts.length > 0 && (
          <ul
            role="alert"
            className="border-destructive/40 text-destructive flex flex-col gap-1 rounded-xl border p-4 text-sm"
          >
            {fieldConflicts.map((conflict) => (
              <li key={conflict.field}>
                {conflict.field}: {conflict.reason}
              </li>
            ))}
          </ul>
        )}

        <Tabs value={tab} onValueChange={setTab}>
          <TabsList
            aria-label="Output"
            className="flex-wrap justify-start group-data-horizontal/tabs:h-auto"
          >
            <TabsTrigger value="config" className="flex-none">
              Config
            </TabsTrigger>
            <TabsTrigger value="migrations" className="flex-none">
              Migrations
            </TabsTrigger>
            <TabsTrigger value="wiring" className="flex-none">
              lib/blocks.ts
            </TabsTrigger>
            <TabsTrigger value="graph" className="flex-none">
              Graph
            </TabsTrigger>
          </TabsList>
          <TabsContent value="config" className="pt-2">
            <CodePanel
              filename="better-supabase.config.ts"
              code={configSource}
            />
          </TabsContent>
          <TabsContent value="migrations" className="pt-2">
            <Suspense
              fallback={
                <p className="text-muted-foreground text-sm" aria-live="polite">
                  Rendering the migrations.
                </p>
              }
            >
              <Migrations code={code} />
            </Suspense>
          </TabsContent>
          <TabsContent value="wiring" className="pt-2">
            <CodePanel filename="lib/blocks.ts" code={wiringSource} />
          </TabsContent>
          <TabsContent value="graph" className="pt-2">
            <PresetGraph resolved={resolved} />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
