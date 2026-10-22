"use client";

import type { ReactElement } from "react";

import { FileCodeIcon } from "lucide-react";
import { useId, useState } from "react";

import { Badge } from "@/components/reui/badge";
import {
  Frame,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { CopyButton } from "@/components/site/copy-button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { cn } from "@/lib/utils";

export interface MigrationViewerFile {
  readonly id: string;
  readonly path: string;
  readonly kind: string;
  readonly module: string;
  readonly lines: number;
  readonly contents: string;
  /** Shiki's output, rendered on the server from `contents`. */
  readonly html: string;
}

const linesLabel = (lines: number): string =>
  lines === 1 ? "1 line" : `${String(lines)} lines`;

/**
 * The files `add` writes: a list on the left and the selected file on the
 * right. Every file arrives highlighted, so switching renders without a fetch.
 */
export function MigrationViewer({
  block,
  files,
  initial,
}: {
  /** The block the page is about; its own files get no module badge. */
  block: string;
  files: readonly MigrationViewerFile[];
  initial: string;
}): ReactElement {
  const [selectedId, setSelectedId] = useState(initial);
  const viewerId = useId();
  const selected = files.find((file) => file.id === selectedId) ?? files[0];
  const items = files.map((file) => ({ value: file.id, label: file.path }));

  return (
    <Frame spacing="sm">
      <FrameHeader className="flex-row flex-wrap items-center justify-between gap-2">
        <FrameTitle>
          {files.length === 1 ? "1 file" : `${String(files.length)} files`}
        </FrameTitle>
        <div className="w-full md:hidden">
          <Select
            items={items}
            value={selected?.id ?? null}
            onValueChange={(value) => {
              if (value !== null) {
                setSelectedId(value);
              }
            }}
          >
            <SelectTrigger
              aria-label="Migration file"
              className="w-full font-mono"
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {items.map((item) => (
                <SelectItem
                  key={item.value}
                  value={item.value}
                  className="font-mono"
                >
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </FrameHeader>
      <div className="flex min-w-0 flex-col gap-1 md:flex-row">
        <FramePanel fit className="hidden md:block md:w-64 md:shrink-0">
          <ul
            aria-label="Migration files"
            className="flex max-h-128 flex-col gap-0.5 overflow-y-auto overscroll-contain"
          >
            {files.map((file) => {
              const active = file.id === selected?.id;

              return (
                <li key={file.id}>
                  <button
                    type="button"
                    aria-pressed={active}
                    aria-controls={viewerId}
                    onClick={() => {
                      setSelectedId(file.id);
                    }}
                    className={cn(
                      "flex w-full flex-col gap-1 rounded-md px-2 py-1.5 text-left transition-colors outline-none hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50",
                      active && "bg-muted",
                    )}
                  >
                    <span className="flex min-w-0 items-center gap-1.5">
                      <FileCodeIcon
                        aria-hidden="true"
                        className="size-3.5 shrink-0 text-muted-foreground"
                      />
                      <span
                        className={cn(
                          "min-w-0 font-mono text-xs break-all",
                          active ? "text-foreground" : "text-muted-foreground",
                        )}
                        title={file.path}
                      >
                        {file.path.split("/").at(-1)}
                      </span>
                    </span>
                    <span className="flex flex-wrap items-center gap-1">
                      <Badge variant="outline">{file.kind}</Badge>
                      {file.module === block ? null : (
                        <Badge variant="secondary">{file.module}</Badge>
                      )}
                      <span
                        className={cn(
                          "ml-auto text-xs tabular-nums",
                          active ? "text-foreground" : "text-muted-foreground",
                        )}
                      >
                        {linesLabel(file.lines)}
                      </span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </FramePanel>
        {selected === undefined ? null : (
          <FramePanel className="flex min-w-0 flex-col gap-2">
            <div className="flex min-w-0 items-center gap-2">
              <code className="min-w-0 truncate font-mono text-xs">
                {selected.path}
              </code>
              <Badge variant="outline" className="md:hidden">
                {selected.kind}
              </Badge>
              <span className="ml-auto shrink-0 text-xs text-muted-foreground tabular-nums">
                {linesLabel(selected.lines)}
              </span>
              <CopyButton
                text={selected.contents}
                label={`Copy ${selected.path}`}
              />
            </div>
            <section
              id={viewerId}

              aria-label={selected.path}
              // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- the code scrolls, so the keyboard needs to reach it
              tabIndex={0}
              className="max-h-128 overflow-auto rounded-md text-code leading-6 outline-none focus-visible:ring-3 focus-visible:ring-ring/50 [&_pre]:font-mono"
              // oxlint-disable-next-line react/no-danger -- Shiki output, rendered on the server from the module registry's SQL.
              dangerouslySetInnerHTML={{ __html: selected.html }}
            />
          </FramePanel>
        )}
      </div>
    </Frame>
  );
}
