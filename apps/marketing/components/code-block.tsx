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
        "border-border bg-card overflow-hidden rounded-xl border text-left shadow-xs",
        className,
      )}
    >
      <figcaption className="border-border text-muted-foreground flex items-center gap-2 border-b px-4 py-2 font-mono text-xs">
        <span aria-hidden="true" className="flex gap-1.5">
          <span className="bg-muted-foreground/30 size-2.5 rounded-full" />
          <span className="bg-muted-foreground/30 size-2.5 rounded-full" />
          <span className="bg-muted-foreground/30 size-2.5 rounded-full" />
        </span>
        {snippet.filename}
      </figcaption>
      <div
        className="text-code overflow-x-auto p-4 leading-6 [&_pre]:font-mono"
        // Shiki output is generated at build time from the static snippets in lib/snippets.ts.
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </figure>
  );
}
