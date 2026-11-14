import { describe, expect, it } from "vitest";

import {
  mainWorktree,
  stripStackKeys,
  withWorkflowWorld,
} from "./worktree-setup.ts";

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

describe("withWorkflowWorld", () => {
  it("adds the world once and keeps a value the file has", () => {
    expect(withWorkflowWorld("A=1")).toBe(
      "A=1\nWORKFLOW_TARGET_WORLD=better-supabase/workflow-sdk/world\n",
    );
    expect(withWorkflowWorld("WORKFLOW_TARGET_WORLD=other\n")).toBe(
      "WORKFLOW_TARGET_WORLD=other\n",
    );
  });
});

describe("stripStackKeys and the signing keys", () => {
  it("keeps SUPABASE_JWKS but drops SUPABASE_JWKS_URL", () => {
    expect(
      stripStackKeys("SUPABASE_JWKS={}\nSUPABASE_JWKS_URL=http://x\n"),
    ).toBe("SUPABASE_JWKS={}\n");
  });
});
