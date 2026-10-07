import { defineSettings } from "better-supabase/blocks/settings";
import * as v from "valibot";

/** The keys the settings SQL module stores, each checked before it writes. */
export const settings = defineSettings({
  user: {
    weeklyDigest: { schema: v.boolean(), default: true },
  },
  organization: {
    defaultRole: {
      schema: v.picklist(["member", "admin"]),
      default: "member",
    },
    weekStart: {
      schema: v.picklist(["monday", "sunday"]),
      default: "monday",
    },
  },
});
