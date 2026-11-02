import { ArrowRightIcon } from "lucide-react";

import { Frame, FramePanel } from "@/components/reui/frame";
import { Section } from "@/components/sections/section";
import { LinkButton } from "@/components/site/link-button";
import { presetGroups } from "@/lib/presets";
import { site } from "@/lib/site";

export function PresetGallery() {
  const groups = presetGroups();

  return (
    <Section
      id="presets"
      eyebrow="Presets"
      title="Start from a product, not an empty schema"
      description="A preset is a named set of blocks with the conventions they share. It installs what it needs and what those require, and you change it afterwards like any other config."
    >
      {groups.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No presets in the catalog yet.
        </p>
      ) : (
        <div className="flex flex-col gap-8">
          {groups.map((group) => (
            <div key={group.title} className="flex flex-col gap-3">
              <h3 className="text-sm font-semibold">
                {group.title}{" "}
                <span className="font-normal text-muted-foreground tabular-nums">
                  {group.presets.length}
                </span>
              </h3>
              <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {group.presets.map((preset) => (
                  <li key={preset.name}>
                    <a
                      href={`${site.create}?preset=${preset.name}`}
                      aria-label={`Create from ${preset.title}, ${String(preset.blocks.length)} blocks`}
                      className="group block h-full outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
                    >
                      <Frame className="h-full transition-colors group-hover:border-foreground/30">
                        <FramePanel className="flex h-full flex-col gap-1">
                          <span className="flex items-baseline justify-between gap-2">
                            <span className="text-sm font-semibold">
                              {preset.title}
                            </span>
                            <span className="text-xs text-muted-foreground tabular-nums">
                              {preset.blocks.length} blocks
                            </span>
                          </span>
                          <span className="line-clamp-3 text-xs leading-5 text-muted-foreground">
                            {preset.description}
                          </span>
                        </FramePanel>
                      </Frame>
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}
      <div className="pt-8">
        <LinkButton variant="outline" href="/docs/presets">
          How presets work
          <ArrowRightIcon aria-hidden="true" />
        </LinkButton>
      </div>
    </Section>
  );
}
