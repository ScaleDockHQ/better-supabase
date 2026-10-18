"use client";

import type { ReactElement } from "react";

import { CheckIcon, CopyIcon } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { Button } from "@/components/ui/button";

/** An icon button that copies `text` and announces "Copied" to screen readers. */
export function CopyButton({
  text,
  label,
  className,
}: {
  text: string;
  label: string;
  className?: string;
}): ReactElement {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(
    () => () => {
      clearTimeout(timer.current);
    },
    [],
  );

  return (
    <>
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label={label}
        className={className}
        onClick={() => {
          void navigator.clipboard.writeText(text).then(() => {
            setCopied(true);
            clearTimeout(timer.current);
            timer.current = setTimeout(() => {
              setCopied(false);
            }, 1500);
          });
        }}
      >
        {copied ? (
          <CheckIcon aria-hidden="true" />
        ) : (
          <CopyIcon aria-hidden="true" />
        )}
      </Button>
      <span aria-live="polite" className="sr-only">
        {copied ? "Copied" : ""}
      </span>
    </>
  );
}
