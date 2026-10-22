import { bsb } from "./server.ts";

Deno.serve(bsb.fetch);
