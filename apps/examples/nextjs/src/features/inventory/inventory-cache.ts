import { tagFor } from "better-supabase/next";

/** Every read of the stock ledger carries this tag; the stock actions expire it. */
export const INVENTORY_TAG = tagFor("inventory");
