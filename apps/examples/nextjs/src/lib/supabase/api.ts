import { app } from "./app.ts";
import { apiBlocks } from "./blocks.api.ts";

/**
 * The app with only the blocks in `gen.serverBlocks.api` on `db`: the teams and
 * permissions blocks next to the app's tables. `/api/v1` builds its server from
 * this, so it bundles no other block (ADR 0542). Server only.
 */
export const betterSupabaseApi = app.blocks(apiBlocks);
