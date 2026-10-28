// The `"use cache: remote"` handler the two-instance e2e test shares
// (next.config.ts sets it when BSB_REMOTE_CACHE_DIR is set).
import process from "node:process";

import { createFileCacheHandler } from "./file-cache-handler.ts";

const dir = process.env["BSB_REMOTE_CACHE_DIR"];

if (!dir) {
  throw new Error("BSB_REMOTE_CACHE_DIR must name the shared cache directory.");
}

export default createFileCacheHandler(dir);
