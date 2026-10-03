import { getLLMText, markdownHeaders, source } from "@/lib/source";

export async function GET() {
  const pages = await Promise.all(source.getPages().map(getLLMText));
  return new Response(pages.join("\n\n"), { headers: markdownHeaders });
}
