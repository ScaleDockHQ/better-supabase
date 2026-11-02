"use client";

import type { ReactNode } from "react";

import { useState } from "react";

import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";

export interface SwitcherItem {
  readonly name: string;
  readonly title: string;
  /** The server-rendered panel: the blocks list and the snippet. */
  readonly panel: ReactNode;
}

/**
 * Switches the preset on the home page. Only the active tab lives on the
 * client; each panel arrives as a server-rendered node, so Shiki and the block
 * icons stay out of the client bundle.
 */
export function PresetSwitcher({
  items,
  initial,
}: {
  items: readonly SwitcherItem[];
  initial: string;
}) {
  const [active, setActive] = useState(initial);

  return (
    <Tabs
      value={active}
      onValueChange={(value) => {
        setActive(String(value));
      }}
      className="w-full gap-4"
    >
      <TabsList
        aria-label="Preset"
        className="h-auto w-full max-w-full justify-start overflow-x-auto"
      >
        {items.map((item) => (
          <TabsTrigger
            key={item.name}
            value={item.name}
            className="px-3 py-1.5"
          >
            {item.title}
          </TabsTrigger>
        ))}
      </TabsList>
      {items.map((item) => (
        <TabsContent key={item.name} value={item.name}>
          {item.panel}
        </TabsContent>
      ))}
    </Tabs>
  );
}
