import { serve } from "./rpc.ts";
import { mapperHandlers } from "./server.ts";

serve(
  mapperHandlers({ env: process.env }),
  process.stdin,
  process.stdout,
  () => {
    process.exit(0);
  },
);
