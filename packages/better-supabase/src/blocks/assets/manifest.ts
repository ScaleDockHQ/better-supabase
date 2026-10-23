import type { BlockOf } from "../define-block.ts";
import type { AssetsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAssets } from "./assets.ts";
import { assetsEvents } from "./events.ts";
import { assetsSqlOptions } from "./options.ts";
import { assetsBinding } from "./record-binding.ts";

/** The `assets` block's manifest (ADR 0029). */
export const assetsBlock: BlockOf<
  "assets",
  typeof createAssets,
  AssetsEvents,
  Record<never, never>,
  never,
  typeof assetsBinding
> = defineBlock({
  name: "assets",
  sql: ["assets"],
  options: { assets: assetsSqlOptions },
  events: assetsEvents,
  create: createAssets,
  record: assetsBinding,
  category: "work",
});
