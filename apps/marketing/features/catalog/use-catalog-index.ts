"use client";

import { useState } from "react";
import * as v from "valibot";

export type CatalogIndex<T> =
  | { readonly status: "idle" | "loading" | "error" }
  | { readonly status: "ready"; readonly items: readonly T[] };

const requests = new Map<string, Promise<unknown>>();

/**
 * Loads a prerendered JSON list the first time `load` runs, and checks it
 * against `schema`. The page keeps its document small by not embedding the
 * list; `load` belongs in an event handler, such as a focus or a change.
 */
export function useCatalogIndex<T>(
  url: string,
  schema: v.GenericSchema<unknown, readonly T[]>,
) {
  const [index, setIndex] = useState<CatalogIndex<T>>({ status: "idle" });

  const load = () => {
    if (index.status === "loading" || index.status === "ready") {
      return;
    }

    setIndex({ status: "loading" });

    let request = requests.get(url);

    if (request === undefined) {
      request = fetch(url).then((response) => {
        if (!response.ok) {
          throw new Error(`${url}: ${String(response.status)}`);
        }

        return response.json();
      });

      requests.set(url, request);
    }

    request
      .then((json) => {
        setIndex({ status: "ready", items: v.parse(schema, json) });
      })
      .catch(() => {
        requests.delete(url);
        setIndex({ status: "error" });
      });
  };

  return { index, load } as const;
}
