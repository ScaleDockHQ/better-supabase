"use client";

import type { ReactNode } from "react";

import { ChevronRightIcon } from "lucide-react";
import { useState } from "react";

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
} from "@/components/ui/sidebar";
import { usePathname } from "@/i18n/navigation";

import type { NavId } from "../nav-items";

import { activeNavId } from "../nav-items";

interface Choice {
  readonly open: boolean;
  readonly forCurrent: boolean;
}

/**
 * One product area of the menu. The server renders the entries and passes them
 * as `children`; this leaf only reads the pathname to open the area that holds
 * the current page, and keeps a choice the user made until they leave.
 */
export function NavArea({
  label,
  ids,
  children,
}: {
  label: string;
  ids: readonly NavId[];
  children: ReactNode;
}) {
  const current = activeNavId(usePathname());
  const holdsCurrent = current !== undefined && ids.includes(current);

  const [choice, setChoice] = useState<Choice | null>(null);

  // A choice applies while the page stays inside or outside the area it was
  // made for; moving into another area hands control back to the pathname.
  const chosen = choice?.forCurrent === holdsCurrent ? choice.open : undefined;

  const open = chosen ?? holdsCurrent;

  return (
    <Collapsible
      open={open}
      onOpenChange={(next) => {
        setChoice({ open: next, forCurrent: holdsCurrent });
      }}
      render={<SidebarGroup />}
    >
      <SidebarGroupLabel
        render={<CollapsibleTrigger className="w-full justify-between" />}
      >
        {label}
        <ChevronRightIcon
          aria-hidden="true"
          className={`transition-transform motion-reduce:transition-none ${open ? "rotate-90" : ""}`}
        />
      </SidebarGroupLabel>
      <CollapsibleContent>
        <SidebarGroupContent>{children}</SidebarGroupContent>
      </CollapsibleContent>
    </Collapsible>
  );
}
