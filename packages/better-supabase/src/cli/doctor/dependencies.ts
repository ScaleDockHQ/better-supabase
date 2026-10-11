import type { Rule } from "./rules.ts";

import { satisfies } from "../peers.ts";

export const DEPENDENCY_RULES: readonly Rule[] = [
  {
    code: "BS601",
    severity: "warning",
    title: "Peer outside its range",
    description:
      "An optional peer of better-supabase is installed at a version outside the range better-supabase declares. With strict peer checks the install fails, and the subpath that needs the peer can break at runtime.",
    check: (context) =>
      (context.peers ?? []).flatMap((peer) =>
        peer.installed !== undefined &&
        satisfies(peer.installed, peer.range) === false
          ? [
              {
                message: `${peer.name}@${peer.installed} is installed, but better-supabase needs ${peer.range}. Install a version in that range, or remove ${peer.name} if nothing imports it.`,
                target: peer.name,
              },
            ]
          : [],
      ),
  },
];
