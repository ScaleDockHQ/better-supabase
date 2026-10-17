import { ArrowRightIcon } from "lucide-react";

import { CodeBlock } from "@/components/code-block";
import { Badge } from "@/components/reui/badge";
import { InstallButton } from "@/components/sections/install-button";
import { LinkButton } from "@/components/site/link-button";
import { site } from "@/lib/site";
import { heroSnippet } from "@/lib/snippets";

export function HomeHero() {
  return (
    <section
      id="hero"
      className="flex w-full items-center justify-center bg-background px-4 py-16 sm:px-6 lg:px-20"
    >
      <div className="mx-auto flex w-full max-w-4xl flex-col items-center gap-8">
        <Badge variant="outline" size="xl" radius="full" className="h-7">
          <span
            aria-hidden="true"
            className="size-1.5 shrink-0 rounded-full bg-brand"
          />
          Open source. MIT. Built on the official Supabase packages.
        </Badge>
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
          <InstallButton command={site.install} />
          <a
            href={site.npm}
            className="text-sm text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
          >
            npm
          </a>
        </div>
        <CodeBlock snippet={heroSnippet} className="w-full max-w-2xl" />
      </div>
    </section>
  );
}
