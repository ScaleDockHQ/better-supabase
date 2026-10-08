"use client";

import {
  diffGraphs,
  type WorkflowGraph,
} from "better-supabase/blocks/workflow-builder";
import { UploadIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

/** What publishing changes against the published version, then a confirm. */
export function PublishDialog({
  published,
  graph,
  pending,
  onPublish,
}: {
  published: { readonly version: number; readonly graph: WorkflowGraph } | null;
  /** The canvas as it is now. */
  graph: WorkflowGraph;
  pending: boolean;
  onPublish: () => void;
}) {
  const t = useExtracted("workflows");
  const diff = diffGraphs(published?.graph ?? { nodes: [], edges: [] }, graph);
  const rows = [
    [t("Nodes added"), diff.nodes.added],
    [t("Nodes removed"), diff.nodes.removed],
    [t("Nodes changed"), diff.nodes.changed],
    [t("Edges added"), diff.edges.added],
    [t("Edges removed"), diff.edges.removed],
  ] as const;
  return (
    <Dialog>
      <DialogTrigger render={<Button size="sm" />}>
        <UploadIcon />
        {t("Publish")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {published === null
              ? t("Publish the first version")
              : t("Publish over version {version}", {
                  version: String(published.version),
                })}
          </DialogTitle>
          <DialogDescription>
            {t(
              "New runs start on the published version. Runs in progress finish on the version they started on.",
            )}
          </DialogDescription>
        </DialogHeader>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          {rows.map(([label, ids]) => (
            <div key={label} className="contents">
              <dt className="text-muted-foreground">{label}</dt>
              <dd className="truncate font-mono text-xs">
                {ids.length === 0 ? "–" : ids.join(", ")}
              </dd>
            </div>
          ))}
        </dl>
        <DialogFooter>
          <DialogClose render={<Button type="button" variant="outline" />}>
            {t("Cancel")}
          </DialogClose>
          <DialogClose
            render={<Button disabled={pending} onClick={onPublish} />}
          >
            {t("Publish")}
          </DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
