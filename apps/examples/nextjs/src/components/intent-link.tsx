"use client";

import type { ComponentProps } from "react";

import type { AppHref } from "@/i18n/navigation";

import { Link, useRouter } from "@/i18n/navigation";

type IntentLinkProps = Omit<
  ComponentProps<typeof Link>,
  "href" | "prefetch"
> & { readonly href: AppHref };

/**
 * A link that fetches its page when the pointer or focus reaches it, not when
 * it scrolls into view. Use it for rows and tiles in long lists, where
 * prefetching every link on screen would cost more than the clicks it saves.
 */
export function IntentLink({
  href,
  onPointerEnter,
  onFocus,
  ...props
}: IntentLinkProps) {
  const { prefetch } = useRouter();

  return (
    <Link
      {...props}
      href={href}
      prefetch={false}
      onPointerEnter={(event) => {
        prefetch(href);
        onPointerEnter?.(event);
      }}
      onFocus={(event) => {
        prefetch(href);
        onFocus?.(event);
      }}
    />
  );
}
