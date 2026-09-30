"use client";

import type { ComponentProps } from "react";

import { appName } from "@/lib/shared";

/** A plain anchor: `/` is served by the marketing app, not by this one. */
export function NavTitle({ href = "/", ...props }: ComponentProps<"a">) {
  return (
    <a href={href} {...props}>
      {appName}
    </a>
  );
}
