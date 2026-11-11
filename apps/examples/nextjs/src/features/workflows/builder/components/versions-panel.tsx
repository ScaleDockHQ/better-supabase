"use client";

import type { WorkflowGraph } from "better-supabase/blocks/workflow-editor";

import { diffGraphs } from "better-supabase/blocks/workflow-editor";
import { useAction } from "better-supabase/react";
import { HistoryIcon, RotateCcwIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { VersionRow } from "../builder-queries";

import { loadVersionGraph } from "../builder-actions";

const STATUS = {
  draft: "info-light",
  published: "success-light",
  archived: "secondary",
} as const satisfies Record<VersionRow["status"], string>;

/**
 * The version history: pick a version to see what it changes against the
 * canvas, then restore it into the draft. Restoring loads the graph onto the
 * canvas (undo goes back); it becomes a version only once it is saved.
 */
export function VersionsPanel({
  versions,
  graph,
  onRestore,
}: {
  versions: readonly VersionRow[];
  /** The canvas as it is now. */
  graph: WorkflowGraph;
  onRestore: (version: VersionRow, graph: WorkflowGraph) => void;
}) {
  const t = useExtracted("workflows");
  const format = useFormatter();
  const errorMessage = useErrorMessage();

  const [picked, setPicked] = useState<{
    readonly version: VersionRow;
    readonly graph: WorkflowGraph;
  } | null>(null);

  const load = useAction(loadVersionGraph, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  if (versions.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <HistoryIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No versions yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Save the draft or publish to start the history.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const diff = picked === null ? null : diffGraphs(picked.graph, graph);

  const rows =
    diff === null
      ? []
      : ([
          [t("Nodes added"), diff.nodes.added],
          [t("Nodes removed"), diff.nodes.removed],
          [t("Nodes changed"), diff.nodes.changed],
          [t("Edges added"), diff.edges.added],
          [t("Edges removed"), diff.edges.removed],
        ] as const);

  return (
    <div className="flex flex-col gap-3">
      <ul className="flex flex-col gap-1">
        {versions.map((version) => (
          <li key={version.id}>
            <Button
              variant={
                picked?.version.id === version.id ? "secondary" : "ghost"
              }
              size="sm"
              className="w-full justify-between"
              disabled={load.pending}
              onClick={() => {
                void load.run({ version: version.id }).then((result) => {
                  if (result.ok) {
                    setPicked({ version, graph: result.data });
                  }
                });
              }}
            >
              <span className="tabular-nums">v{version.version}</span>
              <Badge variant={STATUS[version.status]}>{version.status}</Badge>
              <span className="text-xs text-muted-foreground">
                {format.dateTime(
                  new Date(version.publishedAt ?? version.createdAt),
                  { dateStyle: "short", timeStyle: "short" },
                )}
              </span>
            </Button>
          </li>
        ))}
      </ul>
      {picked === null ? (
        <p className="text-sm text-muted-foreground">
          {t("Select a version to compare it with the canvas.")}
        </p>
      ) : (
        <div className="flex flex-col gap-2" data-testid="version-diff">
          <p className="text-sm font-medium">
            {t("Version {version} compared with the canvas", {
              version: String(picked.version.version),
            })}
          </p>
          <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
            {rows.map(([label, ids]) => (
              <div key={label} className="contents">
                <dt className="text-muted-foreground">{label}</dt>
                <dd className="truncate font-mono text-xs">
                  {ids.length === 0 ? "–" : ids.join(", ")}
                </dd>
              </div>
            ))}
          </dl>
          <Button
            size="sm"
            variant="outline"
            className="w-fit"
            onClick={() => {
              onRestore(picked.version, picked.graph);
            }}
          >
            <RotateCcwIcon />
            {t("Restore into the draft")}
          </Button>
        </div>
      )}
    </div>
  );
}
