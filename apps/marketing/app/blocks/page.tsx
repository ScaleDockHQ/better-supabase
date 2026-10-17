import type { Metadata } from "next";

import { BlocksBrowser } from "@/components/blocks/blocks-browser";
import { blockCategories, blockSummaries } from "@/lib/blocks";

export const metadata: Metadata = {
  title: "Blocks",
  description:
    "Every better-supabase block: the SQL module, what it needs, the modes it supports and the events it writes.",
};

export default function BlocksPage() {
  const blocks = blockSummaries();
  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-10 px-6 py-16 md:px-8">
      <div className="flex max-w-2xl flex-col gap-3">
        <p className="text-xs font-semibold tracking-wide text-brand uppercase">
          Blocks
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">
          Pick the features your app needs
        </h1>
        <p className="text-base leading-7 text-pretty text-muted-foreground">
          Each block is a SQL module in your schema, with a TypeScript side for
          most of them. Install one with{" "}
          <code className="font-mono text-code">
            npx better-supabase sql add
          </code>
          , and the modules it needs come with it. This list is built from the
          module registry, so it matches the package.
        </p>
      </div>
      <BlocksBrowser blocks={blocks} categories={blockCategories} />
    </div>
  );
}
