import { tagFor } from "better-supabase/next";

/**
 * Every read of the shop data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [SHOP_TAG])`. A read in another
 * domain that shows the same rows carries it too.
 */
export const SHOP_TAG = tagFor("shop");
