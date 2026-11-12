import type { ComponentProps } from "react";

import { ArrowLeftIcon } from "lucide-react";

import { buttonVariants } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";

/**
 * The static shell of an admin detail page: a back link above the streamed
 * record.
 */
export function AdminBackLink({
  href,
  children,
}: {
  href: ComponentProps<typeof Link>["href"];
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      className={buttonVariants({
        variant: "ghost",
        size: "sm",
        className: "w-fit",
      })}
    >
      <ArrowLeftIcon />
      {children}
    </Link>
  );
}

/** A label and value pair of a detail card. */
export function Fact({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="min-w-0 text-sm break-words">{children}</dd>
    </div>
  );
}
