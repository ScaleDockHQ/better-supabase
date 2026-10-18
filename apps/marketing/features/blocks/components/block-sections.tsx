import type { ReactNode } from "react";

import { FileCodeIcon } from "lucide-react";

import type { BlockMigrations } from "@/lib/block-migrations";
import type { CatalogBlock } from "@/lib/blocks";

import { Badge } from "@/components/reui/badge";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { LinkButton } from "@/components/site/link-button";
import { SiteLink } from "@/components/site/site-link";
import { blockPath } from "@/lib/blocks";
import { recipePath, recipesFor } from "@/lib/recipes";
import { site } from "@/lib/site";

/** A titled part of the block page; `id` is its anchor in the page rail. */
export function DetailSection({
  id,
  title,
  description,
  children,
}: {
  id: string;
  title: string;
  description?: ReactNode;
  children: ReactNode;
}) {
  const headingId = `${id}-heading`;

  return (
    <section
      id={id}
      aria-labelledby={headingId}
      className="flex scroll-mt-20 flex-col gap-3"
    >
      <div className="flex flex-col gap-1">
        <h2 id={headingId} className="text-xl font-semibold tracking-tight">
          {title}
        </h2>
        {description ? (
          <div className="text-sm leading-6 text-pretty text-muted-foreground">
            {description}
          </div>
        ) : null}
      </div>
      {children}
    </section>
  );
}

function lineCount(contents: string): number {
  return contents.split("\n").length;
}

export function MigrationFiles({
  block,
  migrations,
}: {
  block: CatalogBlock;
  migrations: BlockMigrations;
}) {
  const own = migrations.files.filter((file) => file.module === block.name);

  return (
    <div className="flex flex-col gap-3">
      <Frame spacing="sm">
        <FrameHeader>
          <FrameTitle>
            {migrations.files.length === 1
              ? "1 file"
              : `${String(migrations.files.length)} files`}
          </FrameTitle>
        </FrameHeader>
        <FramePanel>
          <ul className="flex flex-col divide-y divide-border">
            {migrations.files.map((file) => (
              <li
                key={`${file.kind}:${file.path}`}
                className="flex flex-wrap items-center gap-2 py-2 first:pt-0 last:pb-0"
              >
                <FileCodeIcon
                  aria-hidden="true"
                  className="size-4 shrink-0 text-muted-foreground"
                />
                <code className="min-w-0 font-mono text-code break-all">
                  {file.path}
                </code>
                <Badge variant="outline">{file.kind}</Badge>
                {file.module === block.name ? null : (
                  <Badge variant="secondary">{file.module}</Badge>
                )}
                <span className="ml-auto text-xs text-muted-foreground tabular-nums">
                  {lineCount(file.contents)} lines
                </span>
              </li>
            ))}
          </ul>
        </FramePanel>
      </Frame>
      {own.map((file) => (
        <details
          key={`${file.kind}:${file.path}`}
          className="group rounded-xl border border-border bg-card"
        >
          <summary className="cursor-pointer rounded-xl px-4 py-2.5 font-mono text-xs break-all transition-colors hover:bg-muted/50 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none">
            Show {file.path}
          </summary>
          <pre className="max-h-128 overflow-auto border-t border-border p-4 font-mono text-code leading-6">
            {file.contents}
          </pre>
        </details>
      ))}
    </div>
  );
}

export function ClientPanel({ block }: { block: CatalogBlock }) {
  if (block.react) {
    return (
      <Frame spacing="sm">
        <FramePanel className="flex flex-col gap-3">
          <p className="text-sm leading-6 text-muted-foreground">
            The React hooks are in{" "}
            <code className="font-mono text-code text-foreground">
              {block.react.subpath}
            </code>
            . They return data and actions and render no UI, so you build the
            interface from your own components.
          </p>
          <div className="flex flex-wrap gap-2">
            <LinkButton
              variant="outline"
              size="sm"
              href={`${site.github}/blob/main/${block.react.source}`}
            >
              View the React entry
            </LinkButton>
            <LinkButton variant="ghost" size="sm" href={block.docs}>
              Read the docs
            </LinkButton>
          </div>
        </FramePanel>
      </Frame>
    );
  }

  return (
    <p className="text-sm leading-6 text-muted-foreground">
      {block.subpath ? (
        <>
          This block has no React entry yet. Its TypeScript side is in{" "}
          <code className="font-mono text-code text-foreground">
            {block.subpath}
          </code>
          , which runs on the server.
        </>
      ) : (
        "This block is SQL only: call its functions from your policies, RPCs and the other modules."
      )}
    </p>
  );
}

export function EventList({ block }: { block: CatalogBlock }) {
  if (block.events.length === 0) {
    return (
      <p className="text-sm leading-6 text-muted-foreground">
        This module writes no outbox events.
      </p>
    );
  }

  return (
    <ul className="flex flex-wrap gap-1.5">
      {block.events.map((event) => (
        <li key={event}>
          <Badge variant="outline" className="font-mono">
            {event}
          </Badge>
        </li>
      ))}
    </ul>
  );
}

function BlockLinks({
  names,
  empty,
}: {
  names: readonly string[];
  empty: string;
}) {
  if (names.length === 0) {
    return <p className="text-sm text-muted-foreground">{empty}</p>;
  }

  return (
    <ul className="flex flex-wrap gap-1.5">
      {names.map((name) => (
        <li key={name}>
          {name === "*" ? (
            <span className="text-sm text-muted-foreground">every module</span>
          ) : (
            <SiteLink
              href={blockPath(name)}
              className="inline-flex rounded-md border border-border bg-background px-2 py-0.5 font-mono text-xs transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
            >
              {name}
            </SiteLink>
          )}
        </li>
      ))}
    </ul>
  );
}

export function Dependencies({ block }: { block: CatalogBlock }) {
  return (
    <Frame spacing="sm" className="sm:flex-row">
      <FramePanel className="flex flex-col gap-2">
        <FrameTitle>Requires</FrameTitle>
        <FrameDescription>Installed with it by sql add.</FrameDescription>
        <BlockLinks
          names={block.requires}
          empty="Nothing: it installs on its own."
        />
      </FramePanel>
      <FramePanel className="flex flex-col gap-2">
        <FrameTitle>Works with</FrameTitle>
        <FrameDescription>
          Optional modules it integrates with.
        </FrameDescription>
        <BlockLinks
          names={block.integrates}
          empty="No optional integrations."
        />
      </FramePanel>
    </Frame>
  );
}

export function RecipeList({ block }: { block: string }) {
  const recipes = recipesFor(block);

  if (recipes.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No UI recipe uses it yet.{" "}
        <SiteLink href="/recipes" className="text-foreground underline">
          See all recipes
        </SiteLink>
        .
      </p>
    );
  }

  return (
    <ul className="flex flex-wrap gap-2">
      {recipes.map((recipe) => (
        <li key={recipe.slug}>
          {recipe.status === "available" ? (
            <LinkButton
              variant="outline"
              size="sm"
              href={recipePath(recipe.slug)}
            >
              {recipe.title}
            </LinkButton>
          ) : (
            <span className="flex items-center gap-2 text-sm text-muted-foreground">
              {recipe.title}
              <Badge variant="outline">planned</Badge>
            </span>
          )}
        </li>
      ))}
    </ul>
  );
}
