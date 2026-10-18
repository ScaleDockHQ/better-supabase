"use client";

import type { ReactElement } from "react";

import {
  presetApplyCommand,
  presetBlocksSource,
  presetConfigSource,
  presetInstallCommand,
  type ResolvedPreset,
} from "better-supabase/preset";
import { DownloadIcon } from "lucide-react";
import { useId, useMemo, useState } from "react";

import { CopyButton } from "@/components/site/copy-button";
import { PromptFrame } from "@/components/site/prompt-frame";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import {
  commandFor,
  CONFIG_FILE,
  PACKAGE_MANAGERS,
  type PackageManager,
  packagePath,
  withPackage,
} from "@/lib/create";
import {
  type AuthzLibrary,
  FRAMEWORKS,
  PERMDOCK_PEER,
  permDockGenerate,
  permDockInstall,
  withPermDock,
} from "@/lib/create-options";
import { type PromptDesign, presetPrompt } from "@/lib/create-prompt";
import { site } from "@/lib/site";

import { MigrationsPanel } from "./migrations-panel";
import { PresetGraph } from "./preset-graph";

const WIRING_FILE = "lib/blocks.ts";

const NO_DESIGN: PromptDesign = {};

/** The `/create/prompt.md` URL for the same choices, so an agent can fetch it. */
function promptUrl({
  code,
  ui,
  pkg,
  authz,
  manager,
}: {
  code: string;
  ui: boolean;
  pkg: string | undefined;
  authz: AuthzLibrary | undefined;
  manager: PackageManager;
}): string {
  const params = new URLSearchParams({ preset: code });

  if (ui) {
    params.set("ui", "1");
  }

  if (pkg !== undefined) {
    params.set("package", pkg);
  }

  if (authz !== undefined) {
    params.set("authz", authz);
  }

  if (manager !== "pnpm") {
    params.set("manager", manager);
  }

  return `${site.url}/create/prompt.md?${params.toString()}`;
}

function AiInstructions({
  code,
  resolved,
  design,
  designCode,
  pkg,
  authz,
  manager,
}: {
  code: string;
  resolved: ResolvedPreset;
  design: PromptDesign;
  designCode: string;
  pkg: string | undefined;
  authz: AuthzLibrary | undefined;
  manager: PackageManager;
}): ReactElement {
  const ids = useId();
  const [ui, setUi] = useState(false);

  const prompt = useMemo(
    () =>
      presetPrompt({
        resolved,
        design,
        ui,
        manager,
        pkg,
        authz,
        siteUrl: site.url,
      }),
    [resolved, design, ui, manager, pkg, authz],
  );

  const url = promptUrl({ code, ui, pkg, authz, manager });

  return (
    <PromptFrame
      title="AI instructions"
      description={
        designCode === "" ? (
          <>
            Paste this into your coding agent, or have it fetch{" "}
            <a
              href={url}
              className="break-all text-foreground underline underline-offset-4 transition-colors hover:text-primary"
            >
              the Markdown
            </a>
            .
          </>
        ) : (
          "Paste this into your coding agent."
        )
      }
      prompt={prompt}
      copyLabel="Copy AI instructions"
      testId="create-prompt"
    >
      <label
        htmlFor={`${ids}-ui`}
        className="flex cursor-pointer items-center gap-2 text-sm"
      >
        <Switch id={`${ids}-ui`} checked={ui} onCheckedChange={setUi} />
        Include UI
      </label>
    </PromptFrame>
  );
}

function CommandRow({
  label,
  command,
  testId,
}: {
  label: string;
  command: string;
  testId: string;
}): ReactElement {
  return (
    <div className="flex items-center gap-1 rounded-md border border-border bg-muted/50 pl-3">
      <pre className="min-w-0 flex-1 py-2 font-mono text-code break-all whitespace-pre-wrap">
        <code data-testid={testId}>{command}</code>
      </pre>
      <CopyButton text={command} label={`Copy the ${label} command`} />
    </div>
  );
}

function CodePanel({
  filename,
  code,
}: {
  filename: string;
  code: string;
}): ReactElement {
  return (
    <div className="flex flex-col overflow-hidden rounded-lg border border-border">
      <div className="flex items-center justify-between gap-2 border-b border-border bg-muted/40 py-1 pr-1 pl-3">
        <p className="truncate font-mono text-xs text-muted-foreground">
          {filename}
        </p>
        <CopyButton text={code} label={`Copy ${filename}`} />
      </div>
      <section
        aria-label={filename}
        // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- a scrolling region needs keyboard focus (axe scrollable-region-focusable)
        tabIndex={0}
        className="max-h-[min(24rem,40svh)] overflow-auto outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
      >
        <pre className="p-4 font-mono text-code leading-6">
          <code>{code}</code>
        </pre>
      </section>
    </div>
  );
}

function downloadConfig(source: string): void {
  const url = URL.createObjectURL(
    new Blob([source], { type: "text/typescript" }),
  );

  const link = document.createElement("a");
  link.href = url;
  link.download = CONFIG_FILE;
  link.click();
  URL.revokeObjectURL(url);
}

function isPackageManager(value: unknown): value is PackageManager {
  return PACKAGE_MANAGERS.some((each) => each === value);
}

/**
 * The commands for a new or an existing project in the package manager the
 * person picks, then the files those commands write and the AI instructions.
 * `design` holds the app tables and extra columns from the canvas, and
 * `designCode` its URL code; the Markdown link shows only without one,
 * because `/create/prompt.md` reads the preset alone.
 */
export function GetCodeDialog({
  open,
  onOpenChange,
  code,
  resolved,
  pkg,
  authz,
  design = NO_DESIGN,
  designCode = "",
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  code: string;
  resolved: ResolvedPreset;
  pkg: string | undefined;
  authz: AuthzLibrary | undefined;
  design?: PromptDesign;
  designCode?: string;
}): ReactElement {
  const ids = useId();
  const [manager, setManager] = useState<PackageManager>("pnpm");

  const install = commandFor(
    withPackage(presetInstallCommand(resolved), pkg),
    manager,
  );

  const apply = commandFor(
    withPackage(presetApplyCommand(resolved), pkg),
    manager,
  );

  const permDock = authz === "permdock";

  const configSource = permDock
    ? withPermDock(presetConfigSource(resolved))
    : presetConfigSource(resolved);

  const configFile = packagePath(CONFIG_FILE, pkg);
  const wiringFile = packagePath(WIRING_FILE, pkg);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[calc(100svh-2rem)] grid-cols-[minmax(0,1fr)] overflow-y-auto sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>Get the code</DialogTitle>
          <DialogDescription>
            {resolved.blocks.length} blocks on{" "}
            {FRAMEWORKS[resolved.preset.framework].label}. Run one command, or
            copy the files it writes.
          </DialogDescription>
        </DialogHeader>

        <div className="flex min-w-0 flex-col gap-3">
          <Tabs defaultValue="new" className="gap-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <TabsList
                aria-label="Project"
                className="flex-wrap justify-start group-data-horizontal/tabs:h-auto"
              >
                <TabsTrigger value="new">New project</TabsTrigger>
                <TabsTrigger value="existing">Existing project</TabsTrigger>
              </TabsList>
              <ToggleGroup
                aria-label="Package manager"
                variant="outline"
                size="sm"
                spacing={0}
                value={[manager]}
                onValueChange={(value) => {
                  const next = value[0];

                  if (isPackageManager(next)) {
                    setManager(next);
                  }
                }}
              >
                {PACKAGE_MANAGERS.map((each) => (
                  <ToggleGroupItem key={each} value={each}>
                    {each}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
            </div>
            <TabsContent value="new">
              <CommandRow
                label="new project"
                command={install}
                testId="install-command"
              />
            </TabsContent>
            <TabsContent value="existing">
              <CommandRow
                label="existing project"
                command={apply}
                testId="apply-command"
              />
            </TabsContent>
          </Tabs>
          {pkg === undefined ? null : (
            <p id={`${ids}-package`} className="text-xs text-muted-foreground">
              The config and <code className="font-mono">{WIRING_FILE}</code> go
              in <code className="font-mono">{pkg}</code>; the SQL modules stay
              in <code className="font-mono">supabase/</code> at the root.
            </p>
          )}
          {permDock ? (
            <section
              aria-labelledby={`${ids}-permdock`}
              className="flex flex-col gap-2"
            >
              <h3 id={`${ids}-permdock`} className="text-sm font-medium">
                PermDock
              </h3>
              <p className="text-xs text-muted-foreground">
                PermDock 1.0 runs on better-supabase 0.9 (peer{" "}
                <code className="font-mono">{PERMDOCK_PEER}</code>), and both
                releases are about to ship. Add the package, then generate the
                SQL helpers, the token hook,{" "}
                <code className="font-mono">permdock.manifest.json</code> and{" "}
                <code className="font-mono">permissions.catalog.json</code> from
                your PermDock policy; the config reads the two files.
              </p>
              <CommandRow
                label="PermDock install"
                command={permDockInstall(manager, pkg)}
                testId="permdock-install"
              />
              <CommandRow
                label="PermDock generate"
                command={permDockGenerate(manager).join("\n")}
                testId="permdock-generate"
              />
            </section>
          ) : null}
        </div>

        <Tabs defaultValue="config" className="min-w-0 gap-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <TabsList
              aria-label="Generated files"
              className="flex-wrap justify-start group-data-horizontal/tabs:h-auto"
            >
              <TabsTrigger value="config" className="flex-none">
                Config
              </TabsTrigger>
              <TabsTrigger value="migrations" className="flex-none">
                Migrations
              </TabsTrigger>
              <TabsTrigger value="wiring" className="flex-none">
                {WIRING_FILE}
              </TabsTrigger>
              <TabsTrigger value="graph" className="flex-none">
                Graph
              </TabsTrigger>
              <TabsTrigger value="ai" className="flex-none">
                AI instructions
              </TabsTrigger>
            </TabsList>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => {
                downloadConfig(configSource);
              }}
            >
              <DownloadIcon aria-hidden="true" />
              Download config
            </Button>
          </div>
          <TabsContent value="config">
            <CodePanel filename={configFile} code={configSource} />
          </TabsContent>
          <TabsContent value="migrations">
            <MigrationsPanel
              code={code}
              placeholder={resolved.preset.access === "provider"}
            />
          </TabsContent>
          <TabsContent value="wiring">
            <CodePanel
              filename={wiringFile}
              code={presetBlocksSource(resolved)}
            />
          </TabsContent>
          <TabsContent value="graph">
            <PresetGraph resolved={resolved} />
          </TabsContent>
          <TabsContent value="ai" className="min-w-0">
            <AiInstructions
              code={code}
              resolved={resolved}
              design={design}
              designCode={designCode}
              pkg={pkg}
              authz={authz}
              manager={manager}
            />
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}
