"use client";

import type { ComponentProps, CSSProperties, ReactNode } from "react";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";

/** The drawer `Sidebar` renders on a narrow screen. */
export function SidebarMobile({
  open,
  onOpenChange,
  side,
  dir,
  width,
  children,
  ...props
}: Omit<ComponentProps<typeof Sheet>, "children"> & {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  side: "left" | "right";
  dir?: string | undefined;
  width: string;
  children: ReactNode;
}) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange} {...props}>
      <SheetContent
        dir={dir}
        data-sidebar="sidebar"
        data-slot="sidebar"
        data-mobile="true"
        className="w-(--sidebar-width) bg-sidebar p-0 text-sidebar-foreground [&>button]:hidden"
        style={{ "--sidebar-width": width } as CSSProperties}
        side={side}
      >
        <SheetHeader className="sr-only">
          <SheetTitle>Sidebar</SheetTitle>
          <SheetDescription>Displays the mobile sidebar.</SheetDescription>
        </SheetHeader>
        <div className="flex h-full w-full flex-col">{children}</div>
      </SheetContent>
    </Sheet>
  );
}
