import { tagFor } from "better-supabase/next";

/**
 * Every read of the warehouse pages (picks, waves, putaway, cycle counts)
 * carries this tag, and every write of `warehouse-actions.ts` expires it
 * through `refreshCaller(auth, [WAREHOUSE_TAG])`. Pick lists also carry the
 * shop and manufacturing tags, because their documents change them.
 */
export const WAREHOUSE_TAG = tagFor("warehouse");
