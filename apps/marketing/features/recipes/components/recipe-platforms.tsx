"use client";

import type { ReactNode } from "react";

import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";

import type { RecipePlatform } from "@/lib/recipe-platform";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { CopyButton } from "@/components/site/copy-button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { parsePlatform, recipePlatforms } from "@/lib/recipe-platform";

const LABELS = {
  web: "Web",
  native: "Native",
} as const satisfies Record<RecipePlatform, string>;

interface RecipePlatformsProps {
  /** The prompt per platform, built on the server. */
  readonly prompts: Readonly<Record<RecipePlatform, string>>;
  /** The steps per platform, rendered on the server. */
  readonly steps: Readonly<Record<RecipePlatform, ReactNode>>;
  /** Shown between the prompt and the steps, for both platforms. */
  readonly children?: ReactNode;
}

function PromptFrame({
  prompt,
  platform,
}: {
  prompt: string;
  platform: RecipePlatform;
}) {
  return (
    <Frame data-testid="recipe-prompt">
      <FrameHeader className="flex-row items-start justify-between gap-2">
        <div className="flex min-w-0 flex-col gap-1">
          <FrameTitle>Build it with AI</FrameTitle>
          <FrameDescription>
            Paste this into your coding agent. It follows the {LABELS[platform]}{" "}
            tab.
          </FrameDescription>
        </div>
        <CopyButton text={prompt} label="Copy the prompt" />
      </FrameHeader>
      <FramePanel className="p-0">
        <section
          aria-label="Prompt"
          // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- a scrolling region needs keyboard focus (axe scrollable-region-focusable)
          tabIndex={0}
          className="max-h-60 overflow-auto outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
        >
          <pre className="p-4 font-mono text-code leading-6 whitespace-pre-wrap">
            <code data-testid="recipe-prompt-text">{prompt}</code>
          </pre>
        </section>
      </FramePanel>
    </Frame>
  );
}

function PlatformView({
  platform,
  onPlatformChange,
  prompts,
  steps,
  children,
}: RecipePlatformsProps & {
  platform: RecipePlatform;
  onPlatformChange?: (platform: RecipePlatform) => void;
}) {
  return (
    <Tabs
      value={platform}
      onValueChange={(value: string) => {
        onPlatformChange?.(parsePlatform(value));
      }}
      className="gap-8"
    >
      <TabsList aria-label="Platform">
        {recipePlatforms.map((value) => (
          <TabsTrigger key={value} value={value} className="px-4">
            {LABELS[value]}
          </TabsTrigger>
        ))}
      </TabsList>
      <PromptFrame prompt={prompts[platform]} platform={platform} />
      {children}
      {recipePlatforms.map((value) => (
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
 * The Web and Native tabs of a recipe, kept in `?platform=`. The page stays
 * static: the prerendered fallback is the web view, and the search params
 * are read in the browser.
 */
export function RecipePlatforms(props: RecipePlatformsProps) {
  return (
    <Suspense fallback={<PlatformView {...props} platform="web" />}>
      <SearchParamsPlatformView {...props} />
    </Suspense>
  );
}
