import type { NextConfig } from "next";

import { withEve } from "eve/next";

const config: NextConfig = {
  // `next build` needs the TypeScript 6 compiler API; the Turbo `typecheck`
  // task runs TypeScript 7 instead.
  typescript: { ignoreBuildErrors: true },
};

// Starts the agent in agent/ with `next dev` and mounts its routes at
// /eve/v1/*, so the browser calls it on the app's own origin.
export default withEve(config);
