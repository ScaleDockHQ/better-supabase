"use client";

import { useEffect } from "react";

// Few browsers ship WebMCP, so the tools and their schemas load only in one
// that does, instead of in every docs page's bundle. React Compiler cannot
// compile `import()` inside a component, so it stays out here.
async function registerWhenSupported(signal: AbortSignal): Promise<void> {
  if (!("modelContext" in document)) {
    return;
  }

  const { registerDocsWebMcp } = await import("@/lib/webmcp");
  await registerDocsWebMcp(document, signal);
}

/** Offers the docs search and page tools to browser agents that support WebMCP. */
export function WebMcp(): null {
  useEffect(() => {
    const lifetime = new AbortController();
    registerWhenSupported(lifetime.signal).catch(reportError);

    return () => {
      lifetime.abort();
    };
  }, []);

  return null;
}
