import { describe, expect, it } from "vitest";

import { mainWorktree, stripStackKeys } from "./worktree-setup.ts";

describe("stripStackKeys", () => {
  it("drops the keys that point at another checkout's stack or hosts", () => {
    const text = [
      "# comment",
      "SUPABASE_URL=http://127.0.0.1:54321",
      "NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321",
      "export SUPABASE_SECRET_KEY=x",
      "WORKFLOW_POSTGRES_URL=postgres://x",
      "DATABASE_URL=postgres://x",
      "NEXT_PUBLIC_SITE_URL=https://www.localhost",
      "DOCS_ORIGIN=https://docs.localhost",
      "VERCEL_OIDC_TOKEN=token",
      "MY_SUPABASE_NOTE=kept",
      "",
    ].join("\n");

    expect(stripStackKeys(text)).toBe(
      "# comment\nVERCEL_OIDC_TOKEN=token\nMY_SUPABASE_NOTE=kept\n",
    );
  });
});

describe("mainWorktree", () => {
  it("reads the first worktree entry", () => {
    expect(
      mainWorktree(
        "worktree /code/repo\nHEAD abc\nbranch refs/heads/main\n\nworktree /code/repo-x\n",
      ),
    ).toBe("/code/repo");
  });
});
