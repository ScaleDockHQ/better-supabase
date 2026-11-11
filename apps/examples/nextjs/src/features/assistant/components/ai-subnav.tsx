"use client";

import { useExtracted } from "next-intl";

import type { AppHref } from "@/i18n/navigation";

import { buttonVariants } from "@/components/ui/button";
import { Link, usePathname } from "@/i18n/navigation";

const isCurrent = (pathname: string, href: string): boolean =>
  href === "/assistant"
    ? pathname === href
    : pathname === href || pathname.startsWith(`${href}/`);

/**
 * The links between the AI pages: chats, the agent console and the AI
 * operations.
 */
export function AiSubnav() {
  const t = useExtracted("assistant");
  const pathname = usePathname();

  const links: readonly { href: AppHref; label: string }[] = [
    { href: "/assistant", label: t("Chats") },
    { href: "/assistant/agents", label: t("Agents") },
    { href: "/assistant/agents/runs", label: t("Runs") },
    { href: "/assistant/agents/approvals", label: t("Approvals") },
    { href: "/assistant/agents/tools", label: t("Tool access") },
    { href: "/assistant/agents/memory", label: t("Memory") },
    { href: "/assistant/prompts", label: t("Prompts") },
    { href: "/assistant/evals", label: t("Evals") },
    { href: "/assistant/guardrails", label: t("Guardrails") },
    { href: "/assistant/usage", label: t("Usage") },
    { href: "/assistant/tasks", label: t("Schedules") },
    { href: "/assistant/tour", label: t("Tour") },
  ];

  // The deepest matching link is the current one: /assistant/agents/runs is
  // not also "Agents".
  const current = links
    .filter((link) => isCurrent(pathname, link.href))
    .toSorted((a, b) => b.href.length - a.href.length)[0];

  return (
    <nav aria-label={t("AI")} className="flex flex-wrap gap-1">
      {links.map((link) => (
        <Link
          key={link.href}
          href={link.href}
          aria-current={current?.href === link.href ? "page" : undefined}
          className={buttonVariants({
            variant: current?.href === link.href ? "secondary" : "ghost",
            size: "sm",
          })}
        >
          {link.label}
        </Link>
      ))}
    </nav>
  );
}
