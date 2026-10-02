import type { ReactNode } from "react";

import { DocsLayout } from "fumadocs-ui/layouts/docs";

import { AskAI } from "@/components/ask-ai";
import { baseOptions } from "@/lib/layout.shared";
import { source } from "@/lib/source";

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <DocsLayout
      tree={source.getPageTree()}
      // Per-link prefetches carry the prerendered article, so a click paints it at once.
      sidebar={{ prefetch: true }}
      {...baseOptions()}
    >
      {children}
      <AskAI />
    </DocsLayout>
  );
}
