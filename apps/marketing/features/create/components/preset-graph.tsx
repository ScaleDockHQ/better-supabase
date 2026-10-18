import type { ResolvedPreset } from "better-supabase/preset";
import type { ReactElement } from "react";

import { BlocksIcon } from "lucide-react";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  DependencyGraph,
  DependencyLegend,
} from "@/features/blocks/components/dependency-graph";
import {
  columnLayout,
  type DependencyLayout,
  type DependencyNodeSpec,
  getBlock,
} from "@/lib/blocks";
import { presetColumns } from "@/lib/create";

function presetLayout(resolved: ResolvedPreset): DependencyLayout {
  const { columns, edges } = presetColumns(resolved);

  return columnLayout(
    columns.map((column) =>
      column.map((node): DependencyNodeSpec => ({
        id: node.name,
        label: node.name,
        category: getBlock(node.name)?.category ?? null,
        href: null,
        focus: node.selected,
      })),
    ),
    edges,
  );
}

/**
 * The resolved blocks as columns by dependency depth: solid arrows are
 * `requires`, dashed lines the soft integrations between installed blocks.
 */
export function PresetGraph({
  resolved,
}: {
  resolved: ResolvedPreset;
}): ReactElement {
  const layout = presetLayout(resolved);
  const selected = layout.nodes.filter((node) => node.focus).length;

  if (layout.nodes.length === 0) {
    return (
      <Empty className="border border-dashed border-border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <BlocksIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>Pick a block</EmptyTitle>
          <EmptyDescription>
            Select a block to see what it installs and what it works with.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  return (
    <figure className="flex flex-col gap-3">
      <Frame spacing="sm">
        <FrameHeader>
          <DependencyLegend requires="Requires" integrates="Integrates with" />
        </FrameHeader>
        <FramePanel>
          <section
            aria-label="Preset dependency graph"
            // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- the graph scrolls in both directions
            tabIndex={0}
            className="max-h-144 overflow-auto rounded-md outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
          >
            <DependencyGraph
              layout={layout}
              summary={`Dependency graph of ${String(layout.nodes.length)} blocks, ${String(selected)} selected: ${layout.nodes.map((node) => node.label).join(", ")}.`}
            />
          </section>
        </FramePanel>
      </Frame>
      <figcaption className="text-xs leading-5 text-muted-foreground">
        Columns follow dependency depth. Selected blocks have a solid colored
        border; the others are required by a selected block.
      </figcaption>
    </figure>
  );
}
