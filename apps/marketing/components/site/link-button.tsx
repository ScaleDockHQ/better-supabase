import type { VariantProps } from "class-variance-authority";
import type { ReactNode } from "react";

import { SiteLink } from "@/components/site/site-link";
import { buttonVariants } from "@/components/ui/button-variants";

interface LinkButtonProps extends VariantProps<typeof buttonVariants> {
  readonly href: string;
  readonly children: ReactNode;
}

/** A link styled as a button. It renders on the server and ships no JavaScript. */
export function LinkButton({ href, variant, size, children }: LinkButtonProps) {
  return (
    <SiteLink href={href} className={buttonVariants({ variant, size })}>
      {children}
    </SiteLink>
  );
}
