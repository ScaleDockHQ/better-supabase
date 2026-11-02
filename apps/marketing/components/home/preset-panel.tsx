import { ArrowRightIcon } from "lucide-react";
import { Suspense } from "react";

import type { CatalogPreset } from "@/lib/blocks";

import { CodeBlock } from "@/components/code-block";
import { LinkButton } from "@/components/site/link-button";
import { Skeleton } from "@/components/ui/skeleton";
import { BlockIcon } from "@/features/blocks/components/block-icon";
import { presetBlocks, presetSnippet } from "@/lib/presets";
import { site } from "@/lib/site";

const SHOWN = 14;

function SnippetSkeleton() {
  return (
    <output aria-label="Loading the snippet" className="block">
      <Skeleton className="h-64 w-full" />
    </output>
  );
}

/** One preset's blocks and generated config, rendered on the server. */
export function PresetPanel({ preset }: { preset: CatalogPreset }) {
  const { domain, foundationCount, total } = presetBlocks(preset);
  const shown = domain.slice(0, SHOWN);

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <h3 className="text-lg font-semibold tracking-tight">
            {preset.title}
          </h3>
          <p className="text-sm leading-6 text-pretty text-muted-foreground">
            {preset.description}
          </p>
        </div>
        <p className="text-sm font-medium tabular-nums">
          {total} blocks installed
          <span className="font-normal text-muted-foreground">
            {" "}
            ({domain.length} for the product, {foundationCount} foundation)
          </span>
        </p>
        {shown.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            This preset adds only the foundation blocks.
          </p>
        ) : (
          <ul className="flex flex-wrap gap-2">
            {shown.map((block) => (
              <li key={block.name}>
                <a
                  href={`/blocks/${block.name}`}
                  className="inline-flex items-center gap-1.5 rounded-full border border-border py-1 pr-3 pl-1.5 text-sm transition-colors outline-none hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50"
                >
                  <BlockIcon
                    name={block.name}
                    category={block.category}
                    size="xs"
                  />
                  {block.title}
                </a>
              </li>
            ))}
            {domain.length > shown.length ? (
              <li className="inline-flex items-center px-2 text-sm text-muted-foreground tabular-nums">
                +{domain.length - shown.length} more
              </li>
            ) : null}
          </ul>
        )}
        <div className="flex flex-wrap gap-3">
          <LinkButton href={`${site.create}?preset=${preset.name}`}>
            Create from {preset.title}
            <ArrowRightIcon aria-hidden="true" />
          </LinkButton>
          <LinkButton variant="outline" href="/docs/presets">
            About presets
          </LinkButton>
        </div>
      </div>
      <Suspense fallback={<SnippetSkeleton />}>
        <CodeBlock snippet={presetSnippet(preset)} className="w-full" />
      </Suspense>
    </div>
  );
}
