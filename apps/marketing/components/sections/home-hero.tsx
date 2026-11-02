import { ArrowRightIcon, SearchXIcon } from "lucide-react";

import { PresetPanel } from "@/components/home/preset-panel";
import { PresetSwitcher } from "@/components/home/preset-switcher";
import { Frame, FramePanel } from "@/components/reui/frame";
import { CopyCommand } from "@/components/site/copy-command";
import { LinkButton } from "@/components/site/link-button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { blocks } from "@/lib/blocks";
import { getPreset, SWITCHER_PRESETS } from "@/lib/presets";
import { site } from "@/lib/site";

export function HomeHero() {
  const presets = SWITCHER_PRESETS.flatMap((name) => {
    const preset = getPreset(name);

    return preset === undefined ? [] : [preset];
  });

  const first = presets[0];

  return (
    <section
      id="hero"
      className="flex w-full justify-center bg-background px-4 pt-16 pb-12 sm:px-6 lg:px-20"
    >
      <div className="mx-auto flex w-full max-w-6xl flex-col items-center gap-8">
        <a
          href={site.company.url}
          className="inline-flex h-7 items-center rounded-full border border-border px-3 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
        >
          Built by {site.company.name}
        </a>
        <h1 className="max-w-4xl text-center text-4xl font-semibold tracking-tight text-balance text-foreground sm:text-5xl">
          Ship a CRM, helpdesk or ERP on Supabase{" "}
          <span className="text-muted-foreground">
            with {blocks.length} blocks of SQL you own, over your own tables,
            and a typed client on top.
          </span>
        </h1>
        <p className="max-w-xl text-center text-base leading-7 text-muted-foreground">
          Pick a preset, or add one block over a table you already have. Each
          block renders tables, policies and functions into your repository, and
          the CLI types them for you.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-3">
          <LinkButton size="lg" href={site.create}>
            Create from a preset
            <ArrowRightIcon aria-hidden="true" />
          </LinkButton>
          <LinkButton variant="outline" size="lg" href="/blocks">
            Browse the blocks
          </LinkButton>
          <a
            href={site.getStarted}
            className="inline-flex min-h-6 items-center text-sm text-muted-foreground underline-offset-4 transition-colors hover:text-foreground hover:underline"
          >
            Quickstart
          </a>
        </div>
        <CopyCommand command={site.install} />
        <Frame className="w-full">
          <FramePanel>
            {first === undefined ? (
              <Empty>
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <SearchXIcon aria-hidden="true" />
                  </EmptyMedia>
                  <EmptyTitle>No presets in the catalog</EmptyTitle>
                  <EmptyDescription>
                    The catalog lists none yet. Browse the blocks instead.
                  </EmptyDescription>
                </EmptyHeader>
                <LinkButton variant="outline" href="/blocks">
                  Browse the blocks
                </LinkButton>
              </Empty>
            ) : (
              <PresetSwitcher
                initial={first.name}
                items={presets.map((preset) => ({
                  name: preset.name,
                  title: preset.title,
                  panel: <PresetPanel preset={preset} />,
                }))}
              />
            )}
          </FramePanel>
        </Frame>
      </div>
    </section>
  );
}
