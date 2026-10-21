import { toStandardJsonSchema } from "@valibot/to-json-schema";
import { defineSettings } from "better-supabase/blocks/settings";
import * as v from "valibot";

/**
 * The keys the settings SQL module stores, each checked before it writes.
 * `toStandardJsonSchema` adds Standard JSON Schema to each Valibot schema, so
 * `useSettings` reads its kind, choices and title for the preferences page.
 */
export const settings = defineSettings({
  user: {
    weeklyDigest: {
      schema: toStandardJsonSchema(
        v.pipe(
          v.boolean(),
          v.title("Weekly digest"),
          v.description("A Monday summary of your customers."),
        ),
      ),
      default: true,
    },
  },
  organization: {
    defaultRole: {
      schema: toStandardJsonSchema(
        v.pipe(
          v.picklist(["member", "admin"]),
          v.title("Default role for invitations"),
        ),
      ),
      default: "member",
    },
    weekStart: {
      schema: toStandardJsonSchema(
        v.pipe(v.picklist(["monday", "sunday"]), v.title("Week starts on")),
      ),
      default: "monday",
    },
  },
});
