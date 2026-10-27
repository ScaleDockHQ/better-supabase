"use client";

import type { ComponentProps, ReactElement, ReactNode } from "react";

import { CheckIcon, CopyIcon } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { Button } from "@/components/ui/button";

/**
 * A button that copies `text` and announces "Copied" to screen readers: an icon
 * by default, or an icon and `children` as visible text, which `label` must
 * contain so the accessible name includes it.
 */
export function CopyButton({
  text,
  label,
  className,
  variant = "ghost",
  size = "icon-sm",
  disabled = false,
  children,
}: {
  text: string;
  label: string;
  className?: string;
  variant?: ComponentProps<typeof Button>["variant"];
  size?: ComponentProps<typeof Button>["size"];
  disabled?: boolean;
  children?: ReactNode;
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
        type="button"
        variant={variant}
        size={size}
        aria-label={label}
        className={className}
        disabled={disabled}
        onClick={() => {
          void navigator.clipboard.writeText(text).then(() => {
            setCopied(true);
            clearTimeout(timer.current);
            timer.current = setTimeout(() => {
              setCopied(false);
            }, 1500);

            return true;
          });
        }}
      >
        {copied ? (
          <CheckIcon aria-hidden="true" />
        ) : (
          <CopyIcon aria-hidden="true" />
        )}
        {children}
      </Button>
      <span aria-live="polite" className="sr-only">
        {copied ? "Copied" : ""}
      </span>
    </>
  );
}
