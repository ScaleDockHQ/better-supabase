import { notFound } from "next/navigation";

import type { RecipePlatform } from "@/lib/recipe-platform";
import type { AvailableRecipe } from "@/lib/recipes";

import { CodeBlock } from "@/components/code-block";
import { JsonLd } from "@/components/site/json-ld";
import { LinkButton } from "@/components/site/link-button";
import { SiteLink } from "@/components/site/site-link";
import { BlockIcon } from "@/features/blocks/components/block-icon";
import { Breadcrumbs } from "@/features/catalog/components/breadcrumbs";
import { blockPath } from "@/lib/blocks";
import {
  getRecipe,
  recipeCategory,
  recipePath,
  recipePrompt,
  shadcnAdd,
  sourcePath,
} from "@/lib/recipes";
import { site } from "@/lib/site";
import { absoluteUrl, howTo } from "@/lib/structured-data";

import { RecipeCover } from "./recipe-cover";
import { RecipePlatforms } from "./recipe-platforms";
import { RecipeStep, RecipeSteps } from "./recipe-steps";

/** The pieces are the snippet's file name without its folders. */
const fileName = (file: string): string => file.split("/").at(-1) ?? file;

const SNIPPET_LABEL = {
  web: "React and shadcn",
  native: "React Native",
} as const satisfies Record<RecipePlatform, string>;

/** The three steps for one platform; the page renders them once per tab. */
function PlatformSteps({
  recipe,
  platform,
}: {
  recipe: AvailableRecipe;
  platform: RecipePlatform;
}) {
  const side = recipe[platform];
  const addBlock = `npx better-supabase sql add ${recipe.block}`;

  return (
    <RecipeSteps>
      <RecipeStep number={1} title="Add the components">
        {platform === "web" ? (
          <CodeBlock
            snippet={{
              filename: "terminal",
              language: "bash",
              code: shadcnAdd(side.components),
            }}
          />
        ) : (
          <p className="max-w-2xl text-sm leading-6 text-muted-foreground">
            The snippet uses{" "}
            {side.components.map((name, index) => (
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
        )}
      </RecipeStep>

      <RecipeStep number={2} title="Install the glue">
        <p className="max-w-2xl text-sm leading-6 text-muted-foreground">
          Install the block with{" "}
          <code className="font-mono text-code">{addBlock}</code>. The glue
          items are copied into your app, so edit them as you need.
        </p>
        {side.glue.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            None: the hook calls the block from the client.
          </p>
        ) : (
          <CodeBlock
            snippet={{
              filename: "terminal",
              language: "bash",
              code: shadcnAdd(side.glue, true),
            }}
          />
        )}
      </RecipeStep>

      <RecipeStep number={3} title="Write the component">
        <div className="flex min-w-0 flex-col gap-3">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h3 className="text-sm font-semibold">{SNIPPET_LABEL[platform]}</h3>
            <SiteLink
              href={`${site.github}/${sourcePath(side.snippet.file)}`}
              className="text-xs text-muted-foreground underline transition-colors hover:text-foreground"
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
      </RecipeStep>
    </RecipeSteps>
  );
}

/** The recipe page body; it reads `params`, so the route renders it in Suspense. */
export async function RecipeDetail({
  params,
}: {
  readonly params: Promise<{ slug: string }>;
}) {
  const recipe = getRecipe((await params).slug);

  if (!recipe) {
    notFound();
  }

  const { web, hook } = recipe;
  const addBlock = `npx better-supabase sql add ${recipe.block}`;

  return (
    <article className="flex flex-col gap-8">
      <div className="flex flex-col gap-6">
        <Breadcrumbs
          items={[
            { name: "Recipes", href: "/recipes" },
            { name: recipe.title, href: recipePath(recipe.slug) },
          ]}
        />
        <header className="flex flex-col gap-4">
          <h1 className="text-3xl font-semibold tracking-tight">
            {recipe.title}
          </h1>
          <p className="max-w-2xl text-base leading-7 text-pretty text-muted-foreground">
            {recipe.description} Web and native call{" "}
            <code className="font-mono text-code text-foreground">
              {hook.name}
            </code>{" "}
            from{" "}
            <code className="font-mono text-code text-foreground">
              {hook.entry}
            </code>
            .
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <LinkButton
              variant="outline"
              size="sm"
              href={blockPath(recipe.block)}
            >
              <BlockIcon
                name={recipe.block}
                category={recipeCategory(recipe)}
                size="xs"
              />
              The {recipe.block} block
            </LinkButton>
          </div>
        </header>
      </div>

      <RecipePlatforms
        prompts={{
          web: recipePrompt(recipe, "web", site.url),
          native: recipePrompt(recipe, "native", site.url),
        }}
        steps={{
          web: <PlatformSteps recipe={recipe} platform="web" />,
          native: <PlatformSteps recipe={recipe} platform="native" />,
        }}
      >
        <figure className="flex flex-col gap-2">
          <RecipeCover
            recipe={recipe}
            size="lg"
            preload
            className="rounded-xl border border-border"
          />
          <figcaption className="text-sm text-muted-foreground">
            {recipe.screenshot ? (
              "The web version in the Next.js example, signed in as the seed user."
            ) : (
              <>
                No screenshot yet. Run the Next.js example (
                <code className="font-mono text-code">pnpm dev:example</code>)
                to see it.
              </>
            )}
          </figcaption>
        </figure>
      </RecipePlatforms>

      <JsonLd
        data={howTo({
          name: recipe.title,
          description: recipe.description,
          url: absoluteUrl(recipePath(recipe.slug), site.url),
          image: recipe.screenshot
            ? absoluteUrl(recipe.screenshot.src, site.url)
            : null,
          steps: [
            {
              name: "Add the components",
              text: shadcnAdd(web.components),
            },
            {
              name: "Install the glue",
              text: [
                addBlock,
                ...(web.glue.length > 0 ? [shadcnAdd(web.glue, true)] : []),
              ].join(" then "),
            },
            {
              name: "Write the component",
              text: `Call ${hook.name} from ${hook.entry} in your component.`,
            },
          ],
        })}
      />
    </article>
  );
}
