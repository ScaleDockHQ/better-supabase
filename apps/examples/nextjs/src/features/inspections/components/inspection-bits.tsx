"use client";

import { Badge } from "@/components/reui/badge";

import { useFindingTypeLabel, useKindLabel } from "./inspection-labels";

/** An inspection kind in words. */
export function InspectionKind({ kind }: { kind: string }) {
  const label = useKindLabel();

  return <>{label(kind)}</>;
}

/** A finding type as a badge, severe types in a destructive tone. */
export function FindingTypeBadge({ type }: { type: string }) {
  const label = useFindingTypeLabel();

  return (
    <Badge
      variant={
        type === "major_nonconformity"
          ? "destructive-light"
          : type === "minor_nonconformity"
            ? "warning-light"
            : "secondary"
      }
    >
      {label(type)}
    </Badge>
  );
}
