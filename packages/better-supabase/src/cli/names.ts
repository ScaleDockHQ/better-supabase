import type { GenTask, IntegrationName } from "../config/index.ts";

/** The steps `gen` runs, in the order it runs them. */
export const GEN_TASKS: readonly [GenTask, ...GenTask[]] = [
  "types",
  "sql",
  "spec",
  "seed",
  "scaffold",
  "env",
];

export const INTEGRATIONS: readonly [IntegrationName, ...IntegrationName[]] = [
  "next",
  "hono",
  "orpc",
  "edge",
  "expo",
  "mcp",
  "client",
  "react",
];

export const isGenTask = (value: string): value is GenTask =>
  GEN_TASKS.some((task) => task === value);
