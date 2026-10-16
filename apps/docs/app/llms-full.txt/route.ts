import { getFullMarkdown, markdownHeaders } from "@/lib/source";

export async function GET() {
  return new Response(await getFullMarkdown(), { headers: markdownHeaders });
}
