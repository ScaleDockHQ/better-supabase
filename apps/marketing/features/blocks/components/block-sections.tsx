import type { ReactNode } from "react";

import { FileCodeIcon, WorkflowIcon } from "lucide-react";

import type { BlockMigrations } from "@/lib/block-migrations";
import type { CatalogBlock } from "@/lib/blocks";

import { highlight } from "@/components/code-block";
import { Badge } from "@/components/reui/badge";
import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { LinkButton } from "@/components/site/link-button";
import { SiteLink } from "@/components/site/site-link";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { blockGraphLayout, blockGraphSummary, blockPath } from "@/lib/blocks";
import { recipePath, recipesFor } from "@/lib/recipes";
import { site } from "@/lib/site";

import { categoryHref } from "../categories";
import { DependencyGraph, DependencyLegend } from "./dependency-graph";
import { MigrationViewer } from "./migration-viewer";

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
  return contents.replace(/\n$/, "").split("\n").length;
}

/** The files `add` writes, highlighted here and switched on the client. */
export async function MigrationFiles({
  block,
  migrations,
}: {
  block: CatalogBlock;
  migrations: BlockMigrations;
}) {
  const files = await Promise.all(
    migrations.files.map(async (file) => ({
      id: `${file.kind}:${file.path}`,
      path: file.path,
      kind: file.kind,
      module: file.module,
      lines: lineCount(file.contents),
      contents: file.contents,
      html: await highlight(file.contents, "sql"),
    })),
  );

  const first = files.find((file) => file.module === block.name) ?? files.at(0);

  if (first === undefined) {
    return (
      <Empty className="border border-dashed border-border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <FileCodeIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>No SQL files</EmptyTitle>
          <EmptyDescription>
            This block writes nothing into your schema.
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <LinkButton variant="outline" size="sm" href={block.docs}>
            Read the docs
          </LinkButton>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <MigrationViewer block={block.name} files={files} initial={first.id} />
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
              className="inline-flex min-h-6 items-center rounded-md border border-border bg-background px-2 py-0.5 font-mono text-xs transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
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
  const layout = blockGraphLayout(block);

  if (layout.edges.length === 0) {
    return (
      <Empty className="border border-dashed border-border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <WorkflowIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>No dependencies</EmptyTitle>
          <EmptyDescription>
            It installs on its own and integrates with no optional module.
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <LinkButton
            variant="outline"
            size="sm"
            href={categoryHref(block.category)}
          >
            More in {block.category}
          </LinkButton>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <Frame spacing="sm">
      <FrameHeader>
        <DependencyLegend
          requires="Required: the install command adds it too"
          integrates="Works with: optional"
        />
      </FrameHeader>
      <FramePanel>
        <section
          aria-label="Dependency graph"
          // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- a wide graph scrolls sideways on small screens
          tabIndex={0}
          className="overflow-x-auto rounded-md outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
        >
          <DependencyGraph layout={layout} summary={blockGraphSummary(block)} />
        </section>
      </FramePanel>
      <div className="sr-only flex-col gap-3 focus-within:not-sr-only focus-within:flex focus-within:px-3 focus-within:py-2">
        <div className="flex flex-col gap-1.5">
          <span className="text-xs font-medium">Requires</span>
          <BlockLinks
            names={block.requires}
            empty="Nothing: it installs on its own."
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <span className="text-xs font-medium">Works with</span>
          <BlockLinks
            names={block.integrates}
            empty="No optional integrations."
          />
        </div>
      </div>
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
