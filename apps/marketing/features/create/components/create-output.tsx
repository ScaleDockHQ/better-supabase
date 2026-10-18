"use client";

import type { ResolvedPreset } from "better-supabase/preset";

import { CheckIcon, CopyIcon, DownloadIcon } from "lucide-react";
import { useState } from "react";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

import { MigrationsPanel } from "./migrations-panel";
import { PresetGraph } from "./preset-graph";

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <Button
      variant="ghost"
      size="icon-sm"
      aria-label={copied ? "Copied" : label}
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
    </Button>
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
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="flex items-center gap-1 rounded-md border border-border bg-muted/50 pl-3">
        <pre className="min-w-0 flex-1 py-2 font-mono text-code break-all whitespace-pre-wrap">
          <code data-testid={testId}>{command}</code>
        </pre>
        <CopyButton text={command} label={`Copy ${label.toLowerCase()}`} />
      </div>
    </div>
  );
}

function CodePanel({ filename, code }: { filename: string; code: string }) {
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
        className="max-h-[min(32rem,55svh)] overflow-auto outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
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
  link.download = "better-supabase.config.ts";
  link.click();
  URL.revokeObjectURL(url);
}

/** The commands and generated files for the current selection. */
export function CreateOutput({
  code,
  resolved,
  installCommand,
  applyCommand,
  configSource,
  wiringSource,
}: {
  code: string;
  resolved: ResolvedPreset;
  installCommand: string;
  applyCommand: string;
  configSource: string;
  wiringSource: string;
}) {
  return (
    <Frame>
      <FrameHeader>
        <FrameTitle>Your app</FrameTitle>
        <FrameDescription>
          {resolved.blocks.length} blocks on {resolved.preset.framework}. The
          code in the URL restores this selection.
        </FrameDescription>
      </FrameHeader>
      <FramePanel className="flex flex-col gap-4">
        <CommandRow
          label="New project"
          command={installCommand}
          testId="install-command"
        />
        <CommandRow
          label="Existing project"
          command={applyCommand}
          testId="apply-command"
        />
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="min-w-0 truncate font-mono text-xs text-muted-foreground">
            preset: {code}
          </p>
          <Button
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
      </FramePanel>
      <FramePanel>
        <Tabs defaultValue="config" className="gap-3">
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
              lib/blocks.ts
            </TabsTrigger>
            <TabsTrigger value="graph" className="flex-none">
              Graph
            </TabsTrigger>
          </TabsList>
          <TabsContent value="config">
            <CodePanel
              filename="better-supabase.config.ts"
              code={configSource}
            />
          </TabsContent>
          <TabsContent value="migrations">
            <MigrationsPanel code={code} />
          </TabsContent>
          <TabsContent value="wiring">
            <CodePanel filename="lib/blocks.ts" code={wiringSource} />
          </TabsContent>
          <TabsContent value="graph">
            <PresetGraph resolved={resolved} />
          </TabsContent>
        </Tabs>
      </FramePanel>
    </Frame>
  );
}
