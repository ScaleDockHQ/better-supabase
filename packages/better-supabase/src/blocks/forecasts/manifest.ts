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
});
