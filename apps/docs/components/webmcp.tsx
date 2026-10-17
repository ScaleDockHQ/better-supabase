"use client";

import { useEffect } from "react";

import { registerDocsWebMcp } from "@/lib/webmcp";

/** Offers the docs search and page tools to browser agents that support WebMCP. */
export function WebMcp(): null {
  useEffect(() => {
    const lifetime = new AbortController();
    registerDocsWebMcp(document, lifetime.signal).catch(reportError);

    return () => {
      lifetime.abort();
    };
  }, []);

  return null;
}
