"use client";

import { useState } from "react";

/** The ids a user ticked in a list, kept until they clear them. */
export function useRecordSelection() {
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set());

  return {
    selected,
    count: selected.size,
    has: (id: string) => selected.has(id),
    toggle: (id: string) => {
      setSelected((current) => {
        const next = new Set(current);

        if (next.has(id)) {
          next.delete(id);
        } else {
          next.add(id);
        }

        return next;
      });
    },
    setAll: (ids: readonly string[]) => {
      setSelected(new Set(ids));
    },
    clear: () => {
      setSelected(new Set());
    },
  };
}

export type RecordSelection = ReturnType<typeof useRecordSelection>;
