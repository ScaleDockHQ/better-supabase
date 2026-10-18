import { blockMigrations } from "@/lib/block-migrations";
import { blockStaticParams, getBlock } from "@/lib/blocks";
import { blockMarkdown, markdownHeaders } from "@/lib/markdown";
import { recipesFor } from "@/lib/recipes";
import { site } from "@/lib/site";

export function generateStaticParams(): { name: string }[] {
  return blockStaticParams();
}

/** `/blocks/<name>.md`, rewritten here by `proxy.ts`. */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ name: string }> },
): Promise<Response> {
  const { name } = await params;
  const block = getBlock(name);

  if (!block) {
    return new Response("Not found\n", { status: 404 });
  }

  const markdown = blockMarkdown(block, {
    site,
    installed: blockMigrations(name).installed,
    recipes: recipesFor(name),
  });

  return new Response(markdown, { headers: markdownHeaders });
}
