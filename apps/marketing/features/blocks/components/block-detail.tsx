import { BookOpenIcon, CodeIcon } from "lucide-react";
import { notFound } from "next/navigation";

import { CodeBlock } from "@/components/code-block";
import { Badge } from "@/components/reui/badge";
import { CopyCommand } from "@/components/site/copy-command";
import { JsonLd } from "@/components/site/json-ld";
import { LinkButton } from "@/components/site/link-button";
import { categoryHref, categoryStyle } from "@/features/blocks/categories";
import { Breadcrumbs } from "@/features/catalog/components/breadcrumbs";
import { OnThisPage } from "@/features/catalog/components/on-this-page";
import { blockMigrations } from "@/lib/block-migrations";
import {
  blockPath,
  configSnippet,
  getBlock,
  installCommand,
  relatedBlocks,
} from "@/lib/blocks";
import { site } from "@/lib/site";
import { absoluteUrl, blockSource } from "@/lib/structured-data";
import { cn } from "@/lib/utils";

import { BlockIcon } from "./block-icon";
import { BlockPreview } from "./block-preview";
import {
  ClientPanel,
  Dependencies,
  DetailSection,
  EventList,
  MigrationFiles,
  RecipeList,
} from "./block-sections";
import { BlockTile } from "./block-tile";

const SECTIONS = [
  { id: "install", label: "Install" },
  { id: "configure", label: "Configure" },
  { id: "migrations", label: "Migrations" },
  { id: "client", label: "Client" },
  { id: "events", label: "Events" },
  { id: "dependencies", label: "Dependencies" },
  { id: "recipes", label: "Recipes" },
] as const;

/** The block page body; it reads `params`, so the route renders it in Suspense. */
export async function BlockDetail({
  params,
}: {
  readonly params: Promise<{ name: string }>;
}) {
  const block = getBlock((await params).name);

  if (!block) {
    notFound();
  }

  const style = categoryStyle(block.category);
  const migrations = blockMigrations(block.name);
  const install = installCommand(block.name);
  const related = relatedBlocks(block.name);
  const others = migrations.installed.filter((name) => name !== block.name);

  return (
    <div className="flex gap-10">
      <article className="flex min-w-0 flex-1 flex-col gap-10">
        <div className="flex flex-col gap-6">
          <Breadcrumbs
            items={[
              { name: "Blocks", href: "/blocks" },
              { name: block.category, href: categoryHref(block.category) },
              { name: block.title, href: blockPath(block.name) },
            ]}
          />
          <div className="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,20rem)] xl:items-center">
            <header className="flex flex-col gap-4">
              <div className="flex items-center gap-3">
                <BlockIcon
                  name={block.name}
                  category={block.category}
                  size="lg"
                />
                <div className="flex flex-col">
                  <h1 className="text-3xl font-semibold tracking-tight">
                    {block.title}
                  </h1>
                  <span className="font-mono text-xs text-muted-foreground">
                    {block.name}
                  </span>
                </div>
              </div>
              <p className="max-w-2xl text-base leading-7 text-pretty text-muted-foreground">
                {block.description}
              </p>
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="outline">{block.category}</Badge>
                {block.react ? (
                  <Badge variant="primary-light">React hooks</Badge>
                ) : null}
                {block.modes.map((mode) => (
                  <Badge key={mode} variant="secondary">
                    {mode}
                  </Badge>
                ))}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <CopyCommand command={install} />
                <LinkButton variant="outline" size="sm" href={block.docs}>
                  <BookOpenIcon aria-hidden="true" />
                  Docs
                </LinkButton>
                {block.react ? (
                  <LinkButton
                    variant="ghost"
                    size="sm"
                    href={`${site.github}/blob/main/${block.react.source}`}
                  >
                    <CodeIcon aria-hidden="true" />
                    Source
                  </LinkButton>
                ) : null}
              </div>
            </header>
            <BlockPreview
              category={block.category}
              size="lg"
              className={cn(
                "hidden rounded-xl border max-xl:aspect-[21/9] sm:flex",
                style.ring,
              )}
            />
          </div>
        </div>

        <DetailSection
          id="install"
          title="Install"
          description={
            others.length === 0
              ? "It needs no other module."
              : `sql add also installs ${others.join(", ")}, the modules it needs.`
          }
        >
          <CodeBlock
            snippet={{ filename: "terminal", language: "bash", code: install }}
          />
        </DetailSection>

        <DetailSection
          id="configure"
          title="Configure"
          description="The blocks entries in your config, with the default mode."
        >
          <CodeBlock
            snippet={{
              filename: "better-supabase.config.ts",
              language: "ts",
              code: configSnippet(block, migrations.installed),
            }}
          />
        </DetailSection>

        <DetailSection
          id="migrations"
          title="Migrations"
          description={
            <>
              The files <code className="font-mono text-code">{install}</code>{" "}
              writes into your declarative schema with the default layout.
            </>
          }
        >
          <MigrationFiles block={block} migrations={migrations} />
        </DetailSection>

        <DetailSection id="client" title="Client">
          <ClientPanel block={block} />
        </DetailSection>

        <DetailSection
          id="events"
          title="Events"
          description="With the outbox installed, the module writes these in the same transaction as the change."
        >
          <EventList block={block} />
        </DetailSection>

        <DetailSection id="dependencies" title="Dependencies">
          <Dependencies block={block} />
        </DetailSection>

        <DetailSection id="recipes" title="Recipes">
          <RecipeList block={block.name} />
        </DetailSection>

        {related.length === 0 ? null : (
          <section aria-labelledby="related" className="flex flex-col gap-4">
            <h2 id="related" className="text-xl font-semibold tracking-tight">
              More in {block.category}
            </h2>
            <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 2xl:grid-cols-3">
              {related.map((other) => (
                <li key={other.name}>
                  <BlockTile block={other} />
                </li>
              ))}
            </ul>
          </section>
        )}

        <JsonLd
          data={blockSource({
            name: block.name,
            title: block.title,
            description: block.description,
            url: absoluteUrl(blockPath(block.name), site.url),
            docs: absoluteUrl(block.docs, site.url),
            repository: site.github,
          })}
        />
      </article>
      <OnThisPage items={SECTIONS} />
    </div>
  );
}
