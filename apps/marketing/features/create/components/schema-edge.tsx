"use client";

import type { CSSProperties, ReactElement } from "react";

import {
  BaseEdge,
  type Edge,
  EdgeLabelRenderer,
  type EdgeProps,
  getSmoothStepPath,
} from "@xyflow/react";

import type { EdgeKind, Point } from "@/lib/schema-layout";

import { Badge } from "@/components/reui/badge";
import { roundedPath } from "@/lib/schema-layout";
import { cn } from "@/lib/utils";

export interface SchemaEdgeData extends Record<string, unknown> {
  readonly kind: EdgeKind;
  /** The `on delete` action, shown while the edge is highlighted. */
  readonly onDelete: string | null;
  /** One row on each side: a bar at both ends instead of a crow's foot. */
  readonly one: boolean;
  readonly points: readonly Point[];
  /** `false` once an end was dragged: the route no longer meets it. */
  readonly routed: boolean;
  readonly emphasis: "none" | "highlight" | "dim";
}

export type SchemaEdge = Edge<SchemaEdgeData, "schema">;

const MARKER_ONE = "schema-marker-one";
export const MARKER_MANY = "schema-marker-many";

/**
 * The cardinality markers: a bar at the referenced table and a crow's foot
 * at the referencing one, or a bar there too when the referencing column is
 * unique. They draw in the edge's stroke color.
 */
export function SchemaMarkers(): ReactElement {
  return (
    <svg aria-hidden="true" className="absolute size-0">
      <defs>
        <marker
          id={MARKER_ONE}
          viewBox="0 0 12 12"
          refX="1"
          refY="6"
          markerWidth="12"
          markerHeight="12"
          orient="auto-start-reverse"
          markerUnits="userSpaceOnUse"
        >
          <path
            d="M 6 1 L 6 11"
            fill="none"
            stroke="context-stroke"
            strokeWidth="1.5"
          />
        </marker>
        <marker
          id={MARKER_MANY}
          viewBox="0 0 12 12"
          refX="11"
          refY="6"
          markerWidth="12"
          markerHeight="12"
          orient="auto"
          markerUnits="userSpaceOnUse"
        >
          <path
            d="M 1 6 L 11 1 M 1 6 L 11 6 M 1 6 L 11 11"
            fill="none"
            stroke="context-stroke"
            strokeWidth="1.5"
          />
        </marker>
      </defs>
    </svg>
  );
}

/**
 * The ELK route with rounded corners. Once a table is dragged the route no
 * longer meets it, so the edge falls back to a smooth step until Tidy
 * layout routes it again.
 */
export function SchemaEdgeView({
  id,
  data,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
}: EdgeProps<SchemaEdge>): ReactElement {
  const routed = data?.routed === true && data.points.length >= 2;

  const [step, stepX, stepY] = getSmoothStepPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
    borderRadius: 8,
  });

  const path = routed ? roundedPath(data.points) : step;
  const emphasis = data?.emphasis ?? "none";

  const middle = routed
    ? data.points[Math.floor(data.points.length / 2)]
    : undefined;

  const onDelete = data?.onDelete ?? "no action";

  const at: CSSProperties & Record<"--label-x" | "--label-y", string> = {
    "--label-x": `${String(middle?.x ?? stepX)}px`,
    "--label-y": `${String(middle?.y ?? stepY)}px`,
  };

  return (
    <>
      <BaseEdge
        id={id}
        path={path}
        markerStart={`url(#${MARKER_ONE})`}
        markerEnd={`url(#${data?.one === true ? MARKER_ONE : MARKER_MANY})`}
        className={cn(
          "transition-colors",
          data?.kind === "soft" ? "[stroke-dasharray:4_4]" : "",
          emphasis === "highlight"
            ? "stroke-primary! [stroke-width:1.75]"
            : emphasis === "dim"
              ? "[stroke-width:1.25] opacity-30"
              : "stroke-muted-foreground/60! [stroke-width:1.25]",
        )}
      />
      {emphasis === "highlight" && onDelete !== "no action" ? (
        <EdgeLabelRenderer>
          <Badge
            variant="outline"
            className="pointer-events-none absolute top-(--label-y) left-(--label-x) -translate-1/2 bg-background"
            style={at}
          >
            on delete {onDelete}
          </Badge>
        </EdgeLabelRenderer>
      ) : null}
    </>
  );
}
