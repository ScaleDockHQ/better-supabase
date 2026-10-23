import type { DbOf } from "better-supabase";

import { defineDataHooks } from "better-supabase/react";

import type { betterSupabase } from "./supabase";

import { customerColumns, customerList } from "../lists";

type AppDb = DbOf<typeof betterSupabase>;

/**
 * A page of `customerList` with its total, on the provider's engine. The
 * PowerSync engine reads it again when `customers` changes on the device
 * (`tables: { "customer-pages": ["customers"] }`).
 */
export const { useList: useCustomerPage } = defineDataHooks(
  "customer-pages",
  (db: AppDb) => ({
    list: (query: typeof customerList.defaults) =>
      customerList.run(db, query, { select: customerColumns }),
  }),
);
