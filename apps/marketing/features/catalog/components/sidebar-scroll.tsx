"use client";

import type { ReactNode } from "react";

import { usePathname } from "next/navigation";
import { useEffect, useRef } from "react";

import { ScrollArea } from "@/components/ui/scroll-area";

/**
 * A sidebar's scroll container: an overlay scrollbar that shows on hover or
 * while scrolling, edges that fade while there is more to scroll, and the
 * current link scrolled into view when the route changes.
 */
export function SidebarScroll({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const content = useRef<HTMLDivElement>(null);

  useEffect(() => {
    content.current
      ?.querySelector(`a[href="${pathname}"]`)
      ?.scrollIntoView({ block: "nearest" });
  }, [pathname]);

  return (
    <ScrollArea className="sidebar-scroll h-full">
      <div ref={content} className={className}>
        {children}
      </div>
    </ScrollArea>
  );
}
