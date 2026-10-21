"use client";

import type { ReactNode } from "react";

import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";

import type { RecipePlatform } from "@/lib/recipe-platform";

import { PromptFrame } from "@/components/site/prompt-frame";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { parsePlatform } from "@/lib/recipe-platform";

const LABELS = { web: "Web", native: "Native" } as const satisfies Record<
  RecipePlatform,
  string
>;

interface RecipePlatformsProps {
  /** The platforms the recipe has code for, web first. */
  readonly platforms: readonly RecipePlatform[];
  /** The prompt per platform, built on the server. */
  readonly prompts: Readonly<Partial<Record<RecipePlatform, string>>>;
  /** The steps per platform, rendered on the server. */
  readonly steps: Readonly<Partial<Record<RecipePlatform, ReactNode>>>;
  /** Shown between the prompt and the steps, for both platforms. */
  readonly children?: ReactNode;
}

function PlatformView({
  platform: wanted,
  onPlatformChange,
  platforms,
  prompts,
  steps,
  children,
}: RecipePlatformsProps & {
  platform: RecipePlatform;
  onPlatformChange?: (platform: RecipePlatform) => void;
}) {
  const platform = platforms.includes(wanted) ? wanted : "web";

  return (
    <Tabs
      value={platform}
      onValueChange={(value: string) => {
        onPlatformChange?.(parsePlatform(value));
      }}
      className="gap-8"
    >
      {platforms.length > 1 ? (
        <TabsList aria-label="Platform">
          {platforms.map((value) => (
            <TabsTrigger key={value} value={value} className="px-4">
              {LABELS[value]}
            </TabsTrigger>
          ))}
        </TabsList>
      ) : null}
      <PromptFrame
        title="Build it with AI"
        description={`Paste this into your coding agent. It builds the ${LABELS[platform].toLowerCase()} version.`}
        prompt={prompts[platform] ?? ""}
        copyLabel="Copy the prompt"
        testId="recipe-prompt"
      />
      {children}
      {platforms.map((value) => (
        <TabsContent key={value} value={value}>
          {steps[value]}
        </TabsContent>
      ))}
    </Tabs>
  );
}

function SearchParamsPlatformView(props: RecipePlatformsProps) {
  const linked = parsePlatform(useSearchParams().get("platform"));
  const [chosen, setChosen] = useState<RecipePlatform>();

  return (
    <PlatformView
      {...props}
      platform={chosen ?? linked}
      onPlatformChange={(next) => {
        setChosen(next);

        const url = new URL(window.location.href);

        if (next === "web") {
          url.searchParams.delete("platform");
        } else {
          url.searchParams.set("platform", next);
        }

        // `useSearchParams` doesn't follow `replaceState` on this prerendered
        // page, so the tab lives in state and the URL only records it.
        window.history.replaceState(window.history.state, "", url);
      }}
    />
  );
}

/**
 * The Web and Native tabs of a recipe, kept in `?platform=`. A recipe with web
 * code only shows no tabs. The page stays static: the prerendered fallback is
 * the web view, and the search params are read in the browser.
 */
export function RecipePlatforms(props: RecipePlatformsProps) {
  return (
    <Suspense fallback={<PlatformView {...props} platform="web" />}>
      <SearchParamsPlatformView {...props} />
    </Suspense>
  );
}
