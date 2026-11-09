import type { DbOf, AsyncResult } from "better-supabase";

import { defineInfiniteListHook } from "better-supabase/react";

import type { betterSupabase } from "./supabase";

import { customerColumns, customerCursor } from "../lists";

type AppDb = DbOf<typeof betterSupabase>;

interface CustomerRow {
  readonly id: string;
  readonly name: string;
  readonly status: string;
}

interface CustomerCursorArgs {
  readonly after: string | null;
  readonly size: number;
  readonly q?: string;
}

interface CustomerCursorPage {
  readonly items: readonly CustomerRow[];
  readonly nextCursor: string | null;
  readonly hasMore: boolean;
}

function cursorQuery(
  input: CustomerCursorArgs,
): typeof customerCursor.defaults {
  const base = { ...customerCursor.defaults, size: input.size };

  const q = input.q;
  const after = input.after;

  if (q === undefined && after === null) {
    return base;
  }

  if (q === undefined && after !== null) {
    return { ...base, after };
  }

  if (q !== undefined && after === null) {
    return { ...base, q };
  }

  if (q !== undefined && after !== null) {
    return { ...base, q, after };
  }

  return base;
}

/**
 * The next page of customers after `after`. The first page passes `null`.
 * PowerSync reads it again when `customers` changes on the device.
 */
export const useInfiniteCustomers = defineInfiniteListHook(
  "customer-pages",
  (db: AppDb) => ({
    page: (input: CustomerCursorArgs): AsyncResult<CustomerCursorPage> => {
      const query = cursorQuery(input);

      return customerCursor
        .run(db, query, { select: customerColumns })
        .map((page) => ({
          items: page.items,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
        }));
    },
  }),
);
