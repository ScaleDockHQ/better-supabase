import { mcp } from './server.ts';

Deno.serve(mcp.fetch);
