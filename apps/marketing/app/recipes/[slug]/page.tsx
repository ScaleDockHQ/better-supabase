import type { Metadata } from "next";

import { ArrowLeftIcon, BookOpenIcon } from "lucide-react";
import Image from "next/image";
import { notFound } from "next/navigation";

import { CodeBlock } from "@/components/code-block";
import { Badge } from "@/components/reui/badge";
import { LinkButton } from "@/components/site/link-button";
import { SiteLink } from "@/components/site/site-link";
import {
  type AvailableRecipe,
  getRecipe,
  recipeStaticParams,
  shadcnAdd,
  sourcePath,
} from "@/lib/recipes";
import { site } from "@/lib/site";

interface RecipePageProps {
  readonly params: Promise<{ slug: string }>;
}

export function generateStaticParams(): { slug: string }[] {
  return recipeStaticParams();
}

export async function generateMetadata({
  params,
}: RecipePageProps): Promise<Metadata> {
  const recipe = getRecipe((await params).slug);
  if (!recipe) return {};
  return { title: `${recipe.title} recipe`, description: recipe.description };
}

/** The pieces are the snippet's file name without its folders. */
const fileName = (file: string): string => file.split("/").at(-1) ?? file;

function Step({
  number,
  title,
  children,
}: {
  number: number;
  title: string;
  children: React.ReactNode;
}) {
  const id = `step-${String(number)}`;
  return (
    <section aria-labelledby={id} className="flex flex-col gap-4">
      <h2 id={id} className="text-xl font-semibold tracking-tight">
        <span className="mr-2 text-muted-foreground tabular-nums">
          {number}.
        </span>
        {title}
      </h2>
      {children}
    </section>
  );
}

function Screenshot({ recipe }: { recipe: AvailableRecipe }) {
  if (!recipe.screenshot) {
    return (
      <p className="text-sm text-muted-foreground">
        No screenshot yet. Run the Next.js example (
        <code className="font-mono text-code">pnpm dev:example</code>) to see
        it.
      </p>
    );
  }
  return (
    <figure className="flex flex-col gap-2">
      <Image
        src={recipe.screenshot.src}
        width={recipe.screenshot.width}
        height={recipe.screenshot.height}
        alt={`${recipe.title} in the Next.js example`}
        sizes="(min-width: 1152px) 1088px, 100vw"
        className="h-auto w-full rounded-xl border border-border"
      />
      <figcaption className="text-sm text-muted-foreground">
        The web version in the Next.js example, signed in as the seed user.
      </figcaption>
    </figure>
  );
}

export default async function RecipePage({ params }: RecipePageProps) {
  const recipe = getRecipe((await params).slug);
  if (!recipe) notFound();
  const { web, native, hook } = recipe;
  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-12 px-6 py-16 md:px-8">
      <div className="flex flex-col gap-4">
        <SiteLink
          href="/recipes"
          className="inline-flex w-fit items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeftIcon aria-hidden="true" className="size-4" />
          All recipes
        </SiteLink>
        <p className="text-xs font-semibold tracking-wide text-brand uppercase">
          Recipe
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">
          {recipe.title}
        </h1>
        <p className="max-w-2xl text-base leading-7 text-pretty text-muted-foreground">
          {recipe.description} Web and native call{" "}
          <code className="font-mono text-code">{hook.name}</code> from{" "}
          <code className="font-mono text-code">{hook.entry}</code>.
        </p>
        <div className="flex flex-wrap items-center gap-2">
          <LinkButton
            variant="outline"
            size="sm"
            href={`/blocks/${recipe.block}`}
          >
            <BookOpenIcon aria-hidden="true" />
            The {recipe.block} block
          </LinkButton>
          <Badge variant="secondary">Web</Badge>
          <Badge variant="secondary">React Native</Badge>
        </div>
      </div>

      <Step number={1} title="What you build">
        <Screenshot recipe={recipe} />
      </Step>

      <Step number={2} title="Add the components">
        <div className="grid gap-6 lg:grid-cols-2">
          <div className="flex min-w-0 flex-col gap-3">
            <h3 className="text-sm font-semibold">Web: shadcn</h3>
            <CodeBlock
              snippet={{
                filename: "terminal",
                language: "bash",
                code: shadcnAdd(web.components),
              }}
            />
          </div>
          <div className="flex min-w-0 flex-col gap-3">
            <h3 className="text-sm font-semibold">Native: React Native</h3>
            <p className="text-sm leading-6 text-muted-foreground">
              The snippet uses{" "}
              {native.components.map((name, index) => (
                <span key={name}>
                  {index === 0 ? null : ", "}
                  <code className="font-mono text-code">{name}</code>
                </span>
              ))}{" "}
              from <code className="font-mono text-code">react-native</code>, so
              it needs no styling library. For shadcn-style native components,
              React Native Reusables serves them from a registry the shadcn CLI
              reads.
            </p>
          </div>
        </div>
      </Step>

      <Step number={3} title="Install the glue">
        <p className="max-w-2xl leading-7 text-muted-foreground">
          Install the block with{" "}
          <code className="font-mono text-code">
            npx better-supabase sql add {recipe.block}
          </code>
          . The glue items are copied into your app, so edit them as you need.
        </p>
        <div className="grid gap-6 lg:grid-cols-2">
          {[
            { label: "Web", glue: web.glue },
            { label: "Native", glue: native.glue },
          ].map(({ label, glue }) => (
            <div key={label} className="flex min-w-0 flex-col gap-3">
              <h3 className="text-sm font-semibold">{label}</h3>
              {glue.length === 0 ? (
                <p className="text-sm text-muted-foreground">
                  None: the hook calls the block from the client.
                </p>
              ) : (
                <CodeBlock
                  snippet={{
                    filename: "terminal",
                    language: "bash",
                    code: shadcnAdd(glue, true),
                  }}
                />
              )}
            </div>
          ))}
        </div>
      </Step>

      <Step number={4} title="Write the component">
        <div className="grid gap-6 lg:grid-cols-2">
          {[
            { label: "Web: React and shadcn", side: web },
            { label: "Native: React Native", side: native },
          ].map(({ label, side }) => (
            <div key={label} className="flex min-w-0 flex-col gap-3">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <h3 className="text-sm font-semibold">{label}</h3>
                <SiteLink
                  href={`${site.github}/${sourcePath(side.snippet.file)}`}
                  className="text-xs text-muted-foreground underline hover:text-foreground"
                >
                  View in the example
                </SiteLink>
              </div>
              <CodeBlock
                snippet={{
                  filename: fileName(side.snippet.file),
                  language: "tsx",
                  code: side.snippet.code,
                }}
              />
            </div>
          ))}
        </div>
      </Step>
    </div>
  );
}
