import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { extraFieldsArg } from "../shared.ts";
import { RUN_KEYS } from "./workflows-record.ts";

export function workflowsContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const schedules = ctx.hasTable("schedules");
  const semaphores = ctx.hasTable("semaphores");
  const requests = ctx.hasTable("startRequests");
  const keyed = ctx.has("runs", "idempotencyKey");
  const leased = keyed && ctx.has("runs", "dispatchUntil");
  const extras = ctx.extraColumns("runs", RUN_KEYS);

  return [
    {
      name: "record_workflow_run",
      args: [
        "text",
        "text",
        "text",
        "text",
        "{id}",
        "uuid",
        "jsonb",
        "text",
        "timestamptz",
        "timestamptz",
        "text",
        "text",
        "text",
        "text",
        "text",
        "text",
        "text",
        ...extraFieldsArg(extras).contract,
      ],
      returns: "uuid",
    },
    ...(leased
      ? [
          {
            name: "claim_workflow_run_dispatch",
            args: ["uuid", "integer"],
            returns: "jsonb",
          },
          {
            name: "set_workflow_run_engine",
            args: ["uuid", "text", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    {
      name: "workflow_runs_list",
      args: [
        "{id}",
        "text",
        "text",
        "integer",
        "timestamptz",
        "text",
        "text",
        "text",
      ],
      returns: "jsonb",
    },
    { name: "workflow_run_get", args: ["text"], returns: "jsonb" },
    { name: "request_workflow_cancel", args: ["text"], returns: "jsonb" },
    {
      name: "purge_workflow_runs",
      args: ["interval", "integer"],
      returns: "integer",
    },
    ...(schedules
      ? [
          {
            name: "create_workflow_schedule",
            args: [
              "text",
              "text",
              "text",
              "timestamptz",
              "jsonb",
              "text",
              "{id}",
            ],
            returns: "jsonb",
          },
          { name: "workflow_schedules_list", args: ["{id}"], returns: "jsonb" },
          {
            name: "pause_workflow_schedule",
            args: ["uuid", "boolean"],
            returns: "boolean",
          },
          {
            name: "remove_workflow_schedule",
            args: ["uuid"],
            returns: "boolean",
          },
          {
            name: "claim_due_workflow_schedules",
            args: ["integer", "integer"],
            returns: "jsonb",
          },
          {
            name: "advance_workflow_schedule",
            args: ["uuid", "timestamptz", "timestamptz"],
            returns: "boolean",
          },
        ]
      : []),
    ...(semaphores
      ? [
          {
            name: "acquire_workflow_semaphore",
            args: ["text", "text", "integer", "interval"],
            returns: "boolean",
          },
          {
            name: "release_workflow_semaphore",
            args: ["text", "text"],
            returns: "boolean",
          },
        ]
      : []),
    ...(requests
      ? [
          {
            name: "request_workflow_start",
            args: [
              "text",
              "text",
              "jsonb",
              "{id}",
              "uuid",
              "integer",
              "interval",
              "boolean",
              "text",
              "text",
            ],
            returns: "jsonb",
          },
          {
            name: "claim_workflow_start_requests",
            args: ["integer", "integer"],
            returns: "jsonb",
          },
          {
            name: "mark_workflow_start_request",
            args: ["uuid", "text"],
            returns: "boolean",
          },
        ]
      : []),
  ];
}
