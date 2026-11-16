import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { extraFieldsArg } from "../shared.ts";
import { availabilityContract } from "./calendar-availability.ts";
import { calendarBootstrapContract } from "./calendar-bootstrap.ts";
import { defaultAlarmsContract } from "./calendar-default-alarms.ts";
import { calendarFeatures } from "./calendar-features.ts";

/** The functions the generated client wrappers call. */
export function contract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const features = calendarFeatures(ctx);
  const attrs = features.access || features.details;

  return [
    {
      name: "create_calendar",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        ...extraFieldsArg(ctx.extraColumns("calendars", ["fields"])).contract,
        ...(attrs ? ["jsonb"] : []),
      ],
      returns: "jsonb",
    },
    ...(attrs
      ? [
          {
            name: "update_calendar",
            args: ["uuid", "jsonb"],
            returns: "boolean",
          },
        ]
      : []),
    ...(features.grants
      ? [
          {
            name: "set_calendar_grant",
            args: ["uuid", "uuid", "text"],
            returns: "boolean",
          },
          {
            name: "remove_calendar_grant",
            args: ["uuid", "uuid"],
            returns: "boolean",
          },
          { name: "list_calendar_grants", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
    { name: "delete_calendar", args: ["uuid"], returns: "boolean" },
    {
      name: "save_calendar_event",
      args: ["uuid", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "purge_calendar_event", args: ["uuid"], returns: "boolean" },
    {
      name: "cancel_calendar_occurrence",
      args: ["uuid", "timestamptz"],
      returns: "boolean",
    },
    {
      name: "split_calendar_event",
      args: ["uuid", "timestamptz", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "import_calendar_events",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "list_calendar_events",
      args: ["uuid[]", "timestamptz", "timestamptz"],
      returns: "jsonb",
    },
    { name: "page_calendars", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "get_calendar", args: ["uuid"], returns: "jsonb" },
    { name: "page_calendar_events", args: ["jsonb"], returns: "jsonb" },
    { name: "get_calendar_event", args: ["uuid"], returns: "jsonb" },
    { name: "list_calendars", args: ["{id}"], returns: "jsonb" },
    ...calendarBootstrapContract(),
    ...(ctx.hasTable("attendees")
      ? [
          {
            name: "set_calendar_attendee",
            args: ["uuid", "text", "text", "uuid", "text"],
            returns: "boolean",
          },
          {
            name: "respond_calendar_event",
            args: ["uuid", "text"],
            returns: "boolean",
          },
          ...(features.anyAttendee
            ? [
                {
                  name: "set_calendar_attendee",
                  args: ["uuid", "jsonb"],
                  returns: "jsonb",
                },
                {
                  name: "remove_calendar_attendee",
                  args: ["uuid"],
                  returns: "boolean",
                },
              ]
            : []),
        ]
      : []),
    ...availabilityContract(ctx),
    ...defaultAlarmsContract(ctx),
    ...(ctx.installed("share-links")
      ? [{ name: "calendar_feed", args: ["text"], returns: "jsonb" }]
      : []),
    ...(ctx.installed("share-links") && features.userFeed
      ? [{ name: "calendar_user_feed", args: ["text"], returns: "jsonb" }]
      : []),
  ];
}
