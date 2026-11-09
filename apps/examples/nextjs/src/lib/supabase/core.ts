import { app } from "./app.ts";
import { coreBlocks } from "./blocks.core.ts";

/**
 * The app with only the blocks in `gen.serverBlocks.core` on `db`. Routes that
 * read the app's own tables and the permission contract (sign-in, the customers
 * API) build their server from this, so they bundle no other block (ADR 0542).
 * Server only.
 */
export const betterSupabaseCore = app.blocks(coreBlocks);
