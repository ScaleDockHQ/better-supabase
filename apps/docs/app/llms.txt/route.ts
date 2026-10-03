import { getLLMIndex, markdownHeaders } from "@/lib/source";

export async function GET() {
  return new Response(await getLLMIndex(), { headers: markdownHeaders });
}
