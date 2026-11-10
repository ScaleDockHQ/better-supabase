import { blockSummaries } from "@/lib/blocks";

/**
 * Every block's summary, prerendered. The `/blocks` search loads it on first
 * use, so the page's document does not carry the list twice.
 */
export function GET(): Response {
  return Response.json(blockSummaries());
}
