import type { CSSProperties, ReactElement } from "react";

import { createElement, useId } from "react";

import type {
  DependencyEdge,
  DependencyLayout,
  DependencyNode,
} from "@/lib/blocks";

import { cn } from "@/lib/utils";

import { blockIcon } from "../block-icons";
import { categoryStyle } from "../categories";

const TILE = 20;
const ICON = 14;
const INSET = 8;
const LOOP = 28;

/** Below this the labels get too small, so a wider graph scrolls instead. */
const MIN_WIDTH = 480;

/**
 * A curve between the facing sides of two boxes, or a loop out to the right
 * within one column.
 */
function edgePath(
  from: DependencyNode,
  to: DependencyNode,
  layout: DependencyLayout,
): string {
  const middle = layout.nodeHeight / 2;
  const startY = from.y + middle;
  const endY = to.y + middle;

  if (from.x === to.x) {
    const side = from.x + layout.nodeWidth;

    return `M ${String(side)} ${String(startY)} C ${String(side + LOOP)} ${String(startY)}, ${String(side + LOOP)} ${String(endY)}, ${String(side)} ${String(endY)}`;
  }

  const leftward = to.x < from.x;
  const startX = leftward ? from.x : from.x + layout.nodeWidth;
  const endX = leftward ? to.x + layout.nodeWidth : to.x;
  const bend = Math.max(24, Math.abs(startX - endX) / 2) * (leftward ? -1 : 1);

  return `M ${String(startX)} ${String(startY)} C ${String(startX + bend)} ${String(startY)}, ${String(endX - bend)} ${String(endY)}, ${String(endX)} ${String(endY)}`;
}

function GraphNodeBox({
  node,
  layout,
}: {
  node: DependencyNode;
  layout: DependencyLayout;
}): ReactElement {
  const { nodeWidth: width, nodeHeight: height } = layout;

  if (node.category === null) {
    return (
      <g transform={`translate(${String(node.x)} ${String(node.y)})`}>
        <rect
          width={width}
          height={height}
          rx={8}
          className="fill-card stroke-muted-foreground"
          strokeDasharray="4 3"
        />
        <text
          x={INSET + 4}
          y={height / 2}
          dominantBaseline="central"
          className="fill-muted-foreground font-mono text-xs"
        >
          {node.label}
        </text>
      </g>
    );
  }

  const style = categoryStyle(node.category);
  const tileY = (height - TILE) / 2;

  return (
    <g transform={`translate(${String(node.x)} ${String(node.y)})`}>
      <rect
        width={width}
        height={height}
        rx={8}
        className={cn("fill-card", style.text)}
        stroke="currentColor"
        strokeOpacity={node.focus ? 1 : 0.45}
        strokeWidth={node.focus ? 1.5 : 1}
      />
      {node.focus ? (
        <rect
          width={width}
          height={height}
          rx={8}
          fill="currentColor"
          className={cn(style.text, "opacity-10")}
        />
      ) : null}
      <rect
        x={INSET}
        y={tileY}
        width={TILE}
        height={TILE}
        rx={5}
        fill="currentColor"
        fillOpacity={0.15}
        className={style.text}
      />
      {createElement(blockIcon(node.id, node.category), {
        x: INSET + (TILE - ICON) / 2,
        y: tileY + (TILE - ICON) / 2,
        width: ICON,
        height: ICON,
        className: style.text,
      })}
      <text
        x={INSET + TILE + INSET}
        y={height / 2}
        dominantBaseline="central"
        className={cn(
          "fill-foreground font-mono text-xs",
          node.focus && "font-semibold",
        )}
      >
        {node.label}
      </text>
    </g>
  );
}

/**
 * Click targets over the boxes. The graph is one image to assistive tech, so
 * this layer is hidden from it and out of the tab order; the list next to the
 * graph carries the same links for the keyboard and screen readers.
 */
function GraphLinks({ layout }: { layout: DependencyLayout }): ReactElement {
  return (
    <svg
      aria-hidden="true"
      viewBox={`0 0 ${String(layout.width)} ${String(layout.height)}`}
      className="absolute inset-0 size-full"
    >
      {layout.nodes.map((node) =>
        node.href === null || node.category === null ? null : (
          <a
            key={node.id}
            href={node.href}
            tabIndex={-1}
            aria-label={node.label}
          >
            <rect
              x={node.x}
              y={node.y}
              width={layout.nodeWidth}
              height={layout.nodeHeight}
              rx={8}
              fill="currentColor"
              className={cn(
                categoryStyle(node.category).text,
                "opacity-0 transition-opacity hover:opacity-10",
              )}
            />
          </a>
        ),
      )}
    </svg>
  );
}

/**
 * A static dependency graph: boxes in the category's color, solid arrows for
 * `requires` and dashed lines for `integrates`. It uses no state or effects, so
 * it renders on the server and inside client trees alike.
 */
export function DependencyGraph({
  layout,
  summary,
  className,
}: {
  layout: DependencyLayout;
  /** The text alternative of the whole graph. */
  summary: string;
  className?: string;
}): ReactElement {
  const id = useId().replaceAll(/[^\w-]/g, "");
  const arrowId = `${id}-arrow`;
  const titleId = `${id}-title`;
  const byId = new Map(layout.nodes.map((node) => [node.id, node]));

  const pathOf = (edge: DependencyEdge): string | null => {
    const from = byId.get(edge.from);
    const to = byId.get(edge.to);

    return from === undefined || to === undefined
      ? null
      : edgePath(from, to, layout);
  };

  const floor: CSSProperties & Record<"--graph-min-width", string> = {
    "--graph-min-width": `${String(Math.min(layout.width, MIN_WIDTH))}px`,
  };

  return (
    <div
      style={floor}
      className={cn(
        "relative mx-auto w-fit max-w-full min-w-(--graph-min-width)",
        className,
      )}
    >
      <svg
        // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role -- an inline SVG needs role="img" to read as one image (1 finding)
        role="img"
        aria-labelledby={titleId}
        viewBox={`0 0 ${String(layout.width)} ${String(layout.height)}`}
        width={layout.width}
        height={layout.height}
        className="block h-auto w-full"
      >
        <title id={titleId}>{summary}</title>
        <defs>
          <marker
            id={arrowId}
            viewBox="0 0 10 10"
            refX={9}
            refY={5}
            markerWidth={7}
            markerHeight={7}
            orient="auto-start-reverse"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" className="fill-muted-foreground" />
          </marker>
        </defs>
        <g fill="none" className="stroke-muted-foreground">
          {layout.edges.map((edge) => {
            const d = pathOf(edge);

            return d === null ? null : (
              <path
                key={`${edge.kind}:${edge.from}:${edge.to}`}
                d={d}
                strokeWidth={1.25}
                strokeDasharray={edge.kind === "requires" ? undefined : "5 4"}
                markerEnd={
                  edge.kind === "requires" ? `url(#${arrowId})` : undefined
                }
              />
            );
          })}
        </g>
        {layout.nodes.map((node) => (
          <GraphNodeBox key={node.id} node={node} layout={layout} />
        ))}
      </svg>
      <GraphLinks layout={layout} />
    </div>
  );
}

/** The two line styles of `DependencyGraph`, for a caption. */
export function DependencyLegend({
  requires,
  integrates,
}: {
  requires: string;
  integrates: string;
}): ReactElement {
  return (
    <ul className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
      <li className="flex items-center gap-2">
        <svg aria-hidden="true" width={24} height={8} viewBox="0 0 24 8">
          <path
            d="M 0 4 H 20 M 17 1 L 22 4 L 17 7 z"
            className="fill-muted-foreground stroke-muted-foreground"
            strokeWidth={1.25}
          />
        </svg>
        {requires}
      </li>
      <li className="flex items-center gap-2">
        <svg aria-hidden="true" width={24} height={8} viewBox="0 0 24 8">
          <path
            d="M 0 4 H 24"
            fill="none"
            className="stroke-muted-foreground"
            strokeWidth={1.25}
            strokeDasharray="5 4"
          />
        </svg>
        {integrates}
      </li>
    </ul>
  );
}
