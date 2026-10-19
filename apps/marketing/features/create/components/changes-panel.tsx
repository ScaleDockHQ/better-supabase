"use client";

import type { CreateDesign, DesignChange } from "better-supabase/preset";

import { diffDesigns } from "better-supabase/preset";
import { GitCompareArrowsIcon, TriangleAlertIcon } from "lucide-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Frame, FramePanel } from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";

function ChangeRow({ change }: { change: DesignChange }) {
  return (
    <li className="flex flex-col gap-2 px-2 py-2">
      <div className="flex items-start gap-2">
        <Badge
          variant={change.breaking ? "destructive-light" : "success-light"}
        >
          {change.breaking ? "Breaking" : "Safe"}
        </Badge>
        <span className="text-sm">{change.summary}</span>
      </div>
      {change.steps.length === 0 ? null : (
        <ol
          aria-label={`Steps for: ${change.summary}`}
          className="ml-5 flex list-decimal flex-col gap-1 text-xs text-muted-foreground"
        >
          {change.steps.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ol>
      )}
    </li>
  );
}

/**
 * What changed in the app tables since the page loaded: against the design
 * in the link, or against no app tables when the page had none. Breaking
 * changes carry the expand-and-contract steps `apply` prints.
 */
export function ChangesPanel({
  baseline,
  design,
  linked,
  onEdit,
}: {
  baseline: CreateDesign;
  design: CreateDesign;
  linked: boolean;
  onEdit: () => void;
}) {
  const changes = diffDesigns(baseline, design);
  const breaking = changes.filter((change) => change.breaking).length;
  const since = linked ? "the design in your link" : "an empty project";

  if (changes.length === 0) {
    return (
      <Empty className="border border-dashed p-6">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <GitCompareArrowsIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>No changes yet</EmptyTitle>
          <EmptyDescription>
            The app tables match {since}. Edit them on the canvas to see what
            each change does to rows you already have.
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Button type="button" variant="outline" size="sm" onClick={onEdit}>
            Edit the canvas
          </Button>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm leading-6 text-muted-foreground">
        {changes.length} {changes.length === 1 ? "change" : "changes"} to the
        app tables since {since}.
      </p>
      {breaking === 0 ? null : (
        <Alert variant="warning">
          <TriangleAlertIcon aria-hidden="true" />
          <AlertTitle>
            {breaking} breaking {breaking === 1 ? "change" : "changes"}
          </AlertTitle>
          <AlertDescription>
            <code className="font-mono">apply</code> refuses these on a project
            that has the tables. Follow the steps under each, or pass{" "}
            <code className="font-mono">--allow-breaking</code> when the tables
            hold no data yet.
          </AlertDescription>
        </Alert>
      )}
      <Frame spacing="sm">
        <FramePanel>
          <ul aria-label="Changes" className="flex flex-col divide-y">
            {changes.map((change) => (
              <ChangeRow
                key={`${change.kind}:${change.table}:${change.column ?? ""}`}
                change={change}
              />
            ))}
          </ul>
        </FramePanel>
      </Frame>
    </div>
  );
}
