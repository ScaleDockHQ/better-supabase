import { cacheLife } from "next/cache";
import { codeToHtml } from "shiki";

import type { Snippet } from "@/lib/snippets";

import { cn } from "@/lib/utils";

/** Shiki reads the clock while highlighting, so the result is cached per snippet. */
async function highlight(code: string, lang: string): Promise<string> {
  "use cache";
  cacheLife("max");
  return codeToHtml(code, {
    lang,
    themes: { light: "github-light", dark: "github-dark" },
    defaultColor: "light",
  });
}

export async function CodeBlock({
  snippet,
  className,
}: {
  snippet: Snippet;
  className?: string;
}) {
  const html = await highlight(snippet.code, snippet.language);
  return (
    <figure
      className={cn(
        "overflow-hidden rounded-xl border border-border bg-card text-left shadow-xs",
        className,
      )}
    >
      <figcaption className="flex items-center gap-2 border-b border-border px-4 py-2 font-mono text-xs text-muted-foreground">
        <span aria-hidden="true" className="flex gap-1.5">
          <span className="size-2.5 rounded-full bg-muted-foreground/30" />
          <span className="size-2.5 rounded-full bg-muted-foreground/30" />
          <span className="size-2.5 rounded-full bg-muted-foreground/30" />
        </span>
        {snippet.filename}
      </figcaption>
      <div
        className="overflow-x-auto p-4 text-code leading-6 [&_pre]:font-mono"
        // Shiki output is generated at build time from the static snippets in lib/snippets.ts.
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </figure>
  );
}
