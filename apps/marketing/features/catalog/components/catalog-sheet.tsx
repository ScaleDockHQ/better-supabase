"use client";

import type { ReactNode } from "react";

import { PanelLeftIcon } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";

/** The catalog sidebar on small screens. A tap on any link closes it. */
export function CatalogSheet({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger
        render={
          <Button variant="outline" size="sm">
            <PanelLeftIcon aria-hidden="true" />
            Browse the catalog
          </Button>
        }
      />
      <SheetContent side="left">
        <SheetHeader>
          <SheetTitle>Catalog</SheetTitle>
        </SheetHeader>
        {/* oxlint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions -- delegated from the links inside, which handle keys themselves */}
        <div
          className="min-h-0 flex-1 overflow-y-auto px-4 pb-6"
          onClick={(event) => {
            if (event.target instanceof Element && event.target.closest("a")) {
              setOpen(false);
            }
          }}
        >
          {children}
        </div>
      </SheetContent>
    </Sheet>
  );
}
