import { Frame, FramePanel } from "@/components/reui/frame";
import { Section } from "@/components/sections/section";
import { LinkButton } from "@/components/site/link-button";
import { adoptLadder } from "@/lib/home";

export function AdoptLadder() {
  return (
    <Section
      id="adopt"
      eyebrow="Adopt it gradually"
      title="Use it on the app you already have, one rung at a time"
      description="Every rung is optional, independent and reversible, and doctor reports the rung of each table. Stop on any step."
    >
      <Frame>
        <FramePanel>
          <ol className="flex flex-col gap-5">
            {adoptLadder.map((rung, index) => (
              <li
                key={rung.command}
                className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 lg:grid-cols-[auto_minmax(0,24rem)_1fr]"
              >
                <span
                  aria-hidden="true"
                  className="flex size-6 items-center justify-center rounded-full bg-muted text-xs font-semibold tabular-nums"
                >
                  {index + 1}
                </span>
                <code className="self-center font-mono text-sm break-words">
                  better-supabase {rung.command}
                </code>
                <div className="col-start-2 flex flex-col gap-0.5 lg:col-start-3">
                  <p className="text-sm font-medium">{rung.title}</p>
                  <p className="text-sm leading-6 text-muted-foreground">
                    {rung.body}
                  </p>
                </div>
              </li>
            ))}
          </ol>
        </FramePanel>
      </Frame>
      <div className="pt-8">
        <LinkButton variant="outline" href="/docs/blocks/own-schemas">
          Use blocks over your own tables
        </LinkButton>
      </div>
    </Section>
  );
}
