import { docsLlms, markdownHeaders } from "@/lib/source";

export async function GET() {
  return new Response(await docsLlms.full(), { headers: markdownHeaders });
}
