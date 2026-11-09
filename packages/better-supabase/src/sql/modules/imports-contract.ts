import type { BlockSqlContractFunction } from "../context.ts";

import { CHUNK_CONTRACT } from "./imports-chunks.ts";
import { HASH_CONTRACT } from "./imports-hashes.ts";

/** The functions the imports module grants. */
export function importContract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "start_import", args: ["{id}", "text", "jsonb"], returns: "jsonb" },
    {
      name: "start_import_run",
      args: ["{id}", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "get_import_run", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_import_runs",
      args: ["{id}", "text", "text", "integer"],
      returns: "setof jsonb",
    },
    {
      name: "list_import_issues",
      args: ["uuid", "text", "integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "resolve_import_conflict",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "cancel_import_run", args: ["uuid"], returns: "boolean" },
    { name: "mark_import_running", args: ["uuid"], returns: "boolean" },
    {
      name: "finish_import",
      args: ["uuid", "text", "integer", "text"],
      returns: "boolean",
    },
    { name: "begin_import_session", args: ["uuid"], returns: "uuid" },
    {
      name: "import_upsert_batch",
      args: ["uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "import_resolve",
      args: ["uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "finish_import_run", args: ["uuid"], returns: "jsonb" },
    {
      name: "heartbeat_import_run",
      args: ["uuid", "integer"],
      returns: "timestamptz",
    },
    {
      name: "import_ensure_ref",
      args: ["{id}", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "import_entities", args: [], returns: "text[]" },
    {
      name: "rebase_import_records",
      args: ["{id}", "text", "text[]", "text[]"],
      returns: "integer",
    },
    {
      name: "enqueue_import_chunks",
      args: ["uuid", "text", "integer"],
      returns: "integer",
    },
    ...CHUNK_CONTRACT,
    ...HASH_CONTRACT,
  ];
}
