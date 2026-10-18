import { blockGroups } from "@/lib/blocks";
import { blocksIndexMarkdown, markdownHeaders } from "@/lib/markdown";
import { site } from "@/lib/site";

export function GET(): Response {
  return new Response(blocksIndexMarkdown(blockGroups(), site), {
    headers: markdownHeaders,
  });
}
