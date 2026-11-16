import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { archiveContract } from "./bookings-archive.ts";
import { recurringOn } from "./bookings-public.ts";
import { seriesContract } from "./bookings-series.ts";

/** The functions the generated client wrappers call. */
export function contract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_booking_resource",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "set_booking_availability",
      args: ["uuid", "jsonb"],
      returns: "integer",
    },
    {
      name: "add_booking_exception",
      args: ["uuid", "timestamptz", "timestamptz", "boolean", "text"],
      returns: "jsonb",
    },
    { name: "delete_booking_exception", args: ["uuid"], returns: "boolean" },
    { name: "save_booking_service", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "available_slots",
      args: ["uuid", "timestamptz", "timestamptz", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "hold_booking",
      args: ["uuid", "uuid", "timestamptz", "jsonb", "boolean"],
      returns: "jsonb",
    },
    { name: "confirm_booking", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_booking_resources",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "list_booking_services",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    { name: "cancel_booking", args: ["uuid", "text"], returns: "jsonb" },
    { name: "expire_booking_holds", args: [], returns: "integer" },
    { name: "page_bookings", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "get_booking", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_bookings",
      args: ["{id}", "timestamptz", "timestamptz", "uuid", "boolean"],
      returns: "jsonb",
    },
    ...archiveContract(ctx),
    {
      name: "list_bookings_for_customer",
      args: ["{id}", "text", "integer"],
      returns: "jsonb",
    },
    ...(ctx.installed("share-links")
      ? [
          { name: "public_booking_service", args: ["text"], returns: "jsonb" },
          {
            name: "public_available_slots",
            args: ["text", "timestamptz", "timestamptz", "text"],
            returns: "jsonb",
          },
          {
            name: "public_hold_booking",
            args: ["text", "uuid", "timestamptz", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "public_change_booking",
            args: ["uuid", "text", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(recurringOn(ctx) ? seriesContract() : []),
  ];
}
