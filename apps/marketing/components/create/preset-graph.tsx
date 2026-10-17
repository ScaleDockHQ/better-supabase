import type { ResolvedPreset } from "better-supabase/preset";

import { useId } from "react";

import {
  type GraphNode,
  graphLayout,
  NODE_HEIGHT,
  NODE_WIDTH,
} from "@/lib/create";

/** A curve from the left side of `from` to the right side of `to`. */
function edgePath(from: GraphNode, to: GraphNode): string {
  const startX = from.x;
  const startY = from.y + NODE_HEIGHT / 2;
  const endX = to.x + NODE_WIDTH;
  const endY = to.y + NODE_HEIGHT / 2;
  const bend = Math.max(24, Math.abs(startX - endX) / 2);
  return `M ${String(startX)} ${String(startY)} C ${String(startX - bend)} ${String(startY)}, ${String(endX + bend)} ${String(endY)}, ${String(endX)} ${String(endY)}`;
}

/**
 * The resolved blocks as columns by dependency depth: solid lines are
 * `requires`, dashed lines the soft integrations between installed blocks.
 */
export function PresetGraph({ resolved }: { resolved: ResolvedPreset }) {
  const titleId = useId();
  const layout = graphLayout(resolved);
  const byName = new Map(layout.nodes.map((node) => [node.name, node]));
  if (layout.nodes.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Select a block to see its graph.
      </p>
    );
  }
  return (
    <figure className="flex flex-col gap-3">
      <div className="max-h-144 overflow-auto rounded-xl border border-border bg-card p-2">
        <svg
          aria-labelledby={titleId}
          viewBox={`0 0 ${String(layout.width)} ${String(layout.height)}`}
          width={layout.width}
          height={layout.height}
          className="h-auto max-w-full"
        >
          <title id={titleId}>
            {`Dependency graph of ${String(layout.nodes.length)} blocks`}
          </title>
          <g fill="none">
            {layout.edges.map((edge) => {
              const from = byName.get(edge.from);
              const to = byName.get(edge.to);
              if (from === undefined || to === undefined) return null;
              return (
                <path
                  key={`${edge.kind}:${edge.from}:${edge.to}`}
                  d={edgePath(from, to)}
                  className={
                    edge.kind === "requires"
                      ? "stroke-muted-foreground"
                      : "stroke-border"
                  }
                  strokeWidth={1}
                  strokeDasharray={edge.kind === "requires" ? undefined : "4 4"}
                />
              );
            })}
          </g>
          {layout.nodes.map((node) => (
            <g
              key={node.name}
              transform={`translate(${String(node.x)} ${String(node.y)})`}
            >
              <rect
                width={NODE_WIDTH}
                height={NODE_HEIGHT}
                rx={6}
                className={
                  node.selected
                    ? "fill-card stroke-foreground"
                    : "fill-muted stroke-border"
                }
                strokeWidth={1}
              />
              <text
                x={10}
                y={NODE_HEIGHT / 2}
                dominantBaseline="central"
                className="fill-foreground font-mono text-xs"
              >
                {node.name}
              </text>
            </g>
          ))}
        </svg>
      </div>
      <figcaption className="text-xs leading-5 text-muted-foreground">
        Columns follow dependency depth. Outlined blocks are selected, filled
        ones are required by another block. Solid lines are requirements, dashed
        lines the integrations between installed blocks.
      </figcaption>
    </figure>
  );
}
