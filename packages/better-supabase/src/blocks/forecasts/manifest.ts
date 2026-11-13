import type { BlockOf } from "../define-block.ts";
import type { ForecastsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { forecastsEvents } from "./events.ts";
import { createForecasts } from "./forecasts.ts";

/** The `forecasts` block's manifest (ADR 0029). */
export const forecastsBlock: BlockOf<
  "forecasts",
  typeof createForecasts,
  ForecastsEvents
> = defineBlock({
  name: "forecasts",
  sql: ["forecasts"],
  events: forecastsEvents,
  create: createForecasts,
  category: "crm",
  entities: {
    forecast_snapshot: { mutability: "append-only", emits: { create: true } },
  },
  concerns: ["lifecycle"],
  description:
    "Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).",
});
