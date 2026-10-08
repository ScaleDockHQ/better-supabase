import type { ReactNode } from "react";

import { Assistant } from "./assistant";

export default function Page(): ReactNode {
  return (
    <main>
      <h1>Acme assistant</h1>
      <Assistant />
    </main>
  );
}
