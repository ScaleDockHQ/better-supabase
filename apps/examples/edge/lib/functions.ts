import type { SupabaseClient } from "@supabase/supabase-js";

import { functions } from "better-supabase/client";

import type { CreateCustomer } from "../supabase/functions/create-customer/handler.ts";

/** The app's Edge Functions, typed from their own code. */
export type Contracts = { "create-customer": CreateCustomer };

export const edgeFunctions = (supabase: SupabaseClient) =>
  functions<Contracts>(supabase);
