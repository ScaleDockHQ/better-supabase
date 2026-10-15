import type { Metadata } from "next";

import { ArrowLeftIcon, BookOpenIcon } from "lucide-react";
import { notFound } from "next/navigation";

import { CodeBlock } from "@/components/code-block";
import { Badge } from "@/components/reui/badge";
import { LinkButton } from "@/components/site/link-button";
import { SiteLink } from "@/components/site/site-link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { blockMigrations } from "@/lib/block-migrations";
import {
  blockPath,
  blockStaticParams,
  type CatalogBlock,
  configSnippet,
  getBlock,
  installCommand,
} from "@/lib/blocks";
import { recipePath, recipesFor } from "@/lib/recipes";
import { site } from "@/lib/site";

interface BlockPageProps {
  readonly params: Promise<{ name: string }>;
}

export function generateStaticParams(): { name: string }[] {
  return blockStaticParams();
}

export async function generateMetadata({
  params,
}: BlockPageProps): Promise<Metadata> {
  const block = getBlock((await params).name);
  if (!block) return {};
  return { title: `${block.title} block`, description: block.description };
}

function BlockLinks({
  names,
  empty,
}: {
  names: readonly string[];
  empty: string;
}) {
  if (names.length === 0) {
    return <p className="text-muted-foreground text-sm">{empty}</p>;
  }
  return (
    <ul className="flex flex-wrap gap-1.5">
      {names.map((name) => (
        <li key={name}>
          {name === "*" ? (
            <span className="text-muted-foreground text-sm">every module</span>
          ) : (
            <SiteLink
              href={blockPath(name)}
              className="border-border hover:bg-muted rounded-md border px-2 py-0.5 font-mono text-xs transition-colors"
            >
              {name}
            </SiteLink>
          )}
        </li>
      ))}
    </ul>
  );
}

function ClientPanel({ block }: { block: CatalogBlock }) {
  if (block.react) {
    return (
      <div className="flex flex-col gap-3">
        <p className="text-muted-foreground leading-6">
          The React hooks for this block are in{" "}
          <code className="text-code font-mono">{block.react.subpath}</code>.
          They return data and actions and render no UI, so you build the
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
      </div>
    );
  }
  return (
    <p className="text-muted-foreground leading-6">
      {block.subpath ? (
        <>
          This block has no React entry yet. Its TypeScript side is in{" "}
          <code className="text-code font-mono">{block.subpath}</code>, which
          runs on the server.
        </>
      ) : (
        "This block is SQL only: call its functions from your policies, RPCs and the other modules."
      )}
    </p>
  );
}

function EventsPanel({ block }: { block: CatalogBlock }) {
  if (block.events.length === 0) {
    return (
      <p className="text-muted-foreground leading-6">
        This module writes no outbox events.
      </p>
    );
  }
  return (
    <div className="flex flex-col gap-3">
      <p className="text-muted-foreground leading-6">
        With the{" "}
        <SiteLink href="/docs/blocks/outbox" className="underline">
          outbox
        </SiteLink>{" "}
        installed, the module writes these events in the same transaction as the
        change.
      </p>
      <ul className="flex flex-wrap gap-1.5">
        {block.events.map((event) => (
          <li key={event}>
            <Badge variant="outline" className="font-mono">
              {event}
            </Badge>
          </li>
        ))}
      </ul>
    </div>
  );
}

function RecipeLinks({ block }: { block: string }) {
  const recipes = recipesFor(block);
  if (recipes.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">No UI recipe uses it yet.</p>
    );
  }
  return (
    <ul className="flex flex-col gap-1.5">
      {recipes.map((recipe) => (
        <li key={recipe.slug} className="flex items-center gap-2 text-sm">
          {recipe.status === "available" ? (
            <SiteLink href={recipePath(recipe.slug)} className="underline">
              {recipe.title}
            </SiteLink>
          ) : (
            <>
              <span className="text-muted-foreground">{recipe.title}</span>
              <Badge variant="outline">planned</Badge>
            </>
          )}
        </li>
      ))}
    </ul>
  );
}

function lineCount(contents: string): number {
  return contents.split("\n").length;
}

export default async function BlockPage({ params }: BlockPageProps) {
  const block = getBlock((await params).name);
  if (!block) notFound();
  const migrations = blockMigrations(block.name);
  const own = migrations.files.filter((file) => file.module === block.name);
  const install = installCommand(block.name);

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-10 px-6 py-16 md:px-8">
      <div className="flex flex-col gap-4">
        <SiteLink
          href="/blocks"
          className="text-muted-foreground hover:text-foreground inline-flex w-fit items-center gap-1.5 text-sm"
        >
          <ArrowLeftIcon aria-hidden="true" className="size-4" />
          All blocks
        </SiteLink>
        <p className="text-brand text-xs font-semibold tracking-wide uppercase">
          {block.category}
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">{block.title}</h1>
        <p className="text-muted-foreground max-w-2xl text-base leading-7 text-pretty">
          {block.description}
        </p>
        <div className="flex flex-wrap items-center gap-2">
          <LinkButton variant="outline" size="sm" href={block.docs}>
            <BookOpenIcon aria-hidden="true" />
            Docs
          </LinkButton>
          <span className="text-muted-foreground text-sm">Modes:</span>
          {block.modes.map((mode) => (
            <Badge key={mode} variant="secondary">
              {mode}
            </Badge>
          ))}
        </div>
      </div>

      <div className="grid gap-8 lg:grid-cols-3">
        <div className="flex min-w-0 flex-col gap-6 lg:col-span-2">
          <CodeBlock
            snippet={{ filename: "terminal", language: "bash", code: install }}
          />
          <Tabs defaultValue="config">
            <TabsList
              aria-label="Block details"
              className="flex-wrap justify-start group-data-horizontal/tabs:h-auto"
            >
              <TabsTrigger value="config" className="flex-none">
                Config
              </TabsTrigger>
              <TabsTrigger value="migrations" className="flex-none">
                Migrations
              </TabsTrigger>
              <TabsTrigger value="client" className="flex-none">
                Client
              </TabsTrigger>
              <TabsTrigger value="events" className="flex-none">
                Events
              </TabsTrigger>
            </TabsList>
            <TabsContent value="config" keepMounted className="pt-2">
              <CodeBlock
                snippet={{
                  filename: "better-supabase.config.ts",
                  language: "ts",
                  code: configSnippet(block, migrations.installed),
                }}
              />
            </TabsContent>
            <TabsContent
              value="migrations"
              keepMounted
              className="flex flex-col gap-3 pt-2"
            >
              <p className="text-muted-foreground leading-6">
                <code className="text-code font-mono">{install}</code> writes
                these files into your declarative schema with the default
                layout. See{" "}
                <SiteLink href="/docs/blocks/sql" className="underline">
                  SQL modules
                </SiteLink>{" "}
                for the migration step and the layout options.
              </p>
              <ul className="border-border divide-border divide-y rounded-xl border">
                {migrations.files.map((file) => (
                  <li
                    key={`${file.kind}:${file.path}`}
                    className="flex flex-wrap items-center gap-2 px-4 py-2.5"
                  >
                    <code className="text-code min-w-0 font-mono break-all">
                      {file.path}
                    </code>
                    <Badge variant="outline">{file.kind}</Badge>
                    {file.module === block.name ? null : (
                      <Badge variant="secondary">{file.module}</Badge>
                    )}
                    <span className="text-muted-foreground ml-auto text-xs">
                      {lineCount(file.contents)} lines
                    </span>
                  </li>
                ))}
              </ul>
              {own.map((file) => (
                <details
                  key={`${file.kind}:${file.path}`}
                  className="border-border bg-card rounded-xl border"
                >
                  <summary className="cursor-pointer px-4 py-2.5 font-mono text-xs">
                    {file.path}
                  </summary>
                  <pre className="text-code border-border max-h-128 overflow-auto border-t p-4 font-mono leading-6">
                    {file.contents}
                  </pre>
                </details>
              ))}
            </TabsContent>
            <TabsContent value="client" keepMounted className="pt-2">
              <ClientPanel block={block} />
            </TabsContent>
            <TabsContent value="events" keepMounted className="pt-2">
              <EventsPanel block={block} />
            </TabsContent>
          </Tabs>
        </div>
        <aside className="flex flex-col gap-6">
          <div className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold">Requires</h2>
            <BlockLinks
              names={block.requires}
              empty="Nothing: it installs on its own."
            />
          </div>
          <div className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold">Works with</h2>
            <BlockLinks
              names={block.integrates}
              empty="No optional integrations."
            />
          </div>
          <div className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold">Recipes</h2>
            <RecipeLinks block={block.name} />
          </div>
        </aside>
      </div>
    </div>
  );
}
