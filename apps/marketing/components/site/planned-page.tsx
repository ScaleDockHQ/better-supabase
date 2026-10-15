import type { ReactNode } from "react";

import { LinkButton } from "@/components/site/link-button";
import { websitePlan } from "@/lib/site";

interface PlannedPageProps {
  readonly eyebrow: string;
  readonly title: string;
  readonly lead: string;
  readonly children: ReactNode;
}

/** A page whose feature is planned but not built: what is coming and what works today. */
export function PlannedPage({
  eyebrow,
  title,
  lead,
  children,
}: PlannedPageProps) {
  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-8 px-6 py-16 md:px-8">
      <div className="flex flex-col gap-3">
        <p className="text-brand text-xs font-semibold tracking-wide uppercase">
          {eyebrow}
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
        <p className="text-muted-foreground text-base leading-7 text-pretty">
          {lead}
        </p>
      </div>
      <div className="text-muted-foreground [&_h2]:text-foreground [&_code]:text-code flex flex-col gap-4 text-base leading-7 [&_code]:font-mono [&_h2]:text-lg [&_h2]:font-semibold">
        {children}
      </div>
      <div className="flex flex-wrap gap-3">
        <LinkButton href="/blocks">Browse the blocks</LinkButton>
        <LinkButton variant="outline" href={websitePlan}>
          Read the plan
        </LinkButton>
      </div>
    </div>
  );
}
