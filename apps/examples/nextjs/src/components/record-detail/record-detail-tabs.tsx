"use client";

import type { ReactNode } from "react";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

export interface RecordDetailTab {
  readonly value: string;
  readonly label: string;
  readonly content: ReactNode;
}

/**
 * Tabs for a record page (overview, activity, related, files). The server
 * renders each panel and passes it as a node, so a panel's reads still sit
 * behind its own `AfterNavigation`.
 */
export function RecordDetailTabs({
  tabs,
  defaultValue,
}: {
  tabs: readonly RecordDetailTab[];
  defaultValue?: string;
}) {
  const first = tabs[0]?.value;

  return (
    <Tabs defaultValue={defaultValue ?? first}>
      <TabsList>
        {tabs.map((tab) => (
          <TabsTrigger key={tab.value} value={tab.value}>
            {tab.label}
          </TabsTrigger>
        ))}
      </TabsList>
      {tabs.map((tab) => (
        <TabsContent key={tab.value} value={tab.value} className="pt-4">
          {tab.content}
        </TabsContent>
      ))}
    </Tabs>
  );
}
