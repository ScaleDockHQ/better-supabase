import { ArrowRightIcon } from "lucide-react";

import { CodeBlock } from "@/components/code-block";
import { CopyCommand } from "@/components/site/copy-command";
import { LinkButton } from "@/components/site/link-button";
import { categoryStyle } from "@/features/blocks/categories";
import { BlockPreview } from "@/features/blocks/components/block-preview";
import { site } from "@/lib/site";
import { heroSnippet } from "@/lib/snippets";
import { cn } from "@/lib/utils";

const HERO_SCENES = ["Billing & commerce", "AI"] as const;

export function HomeHero() {
  return (
    <section
      id="hero"
      className="flex w-full items-center justify-center bg-background px-4 py-16 sm:px-6 lg:px-20"
    >
      <div className="mx-auto flex w-full max-w-6xl flex-col items-center gap-8">
        <h1 className="max-w-3xl text-center text-4xl font-semibold text-balance text-foreground sm:text-5xl lg:text-6xl">
          The typed layer for Supabase{" "}
          <span className="text-muted-foreground">
            apps, APIs, MCP servers and jobs.
          </span>
        </h1>
        <p className="max-w-xl text-center text-base leading-7 text-muted-foreground">
          Generated models, a typed repository that returns results instead of
          throwing, auth glue that skips needless network calls, and adapters
          for Next.js, Hono, oRPC and Edge Functions.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-3">
          <LinkButton size="lg" href={site.getStarted}>
            Get started
            <ArrowRightIcon aria-hidden="true" />
          </LinkButton>
          <LinkButton variant="outline" size="lg" href={site.github}>
            GitHub
          </LinkButton>
        </div>
        <div className="flex flex-wrap items-center justify-center gap-3">
          <CopyCommand command={site.install} />
          <a
            href={site.npm}
            className="text-sm text-muted-foreground underline-offset-4 transition-colors hover:text-foreground hover:underline"
          >
            npm
          </a>
        </div>
        <div className="grid w-full max-w-5xl grid-cols-1 gap-4 pt-4 lg:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
          <CodeBlock snippet={heroSnippet} className="w-full" />
          <div aria-hidden="true" className="hidden flex-col gap-4 lg:flex">
            {HERO_SCENES.map((category) => (
              <BlockPreview
                key={category}
                category={category}
                className={cn(
                  "aspect-auto min-h-40 flex-1 rounded-xl border",
                  categoryStyle(category).ring,
                )}
              />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
