import { describe, expect, it } from "vitest";

import {
  MAX_BODY_LENGTH,
  changelogSection,
  truncateNotes,
} from "./github-releases.ts";

const changelog = `# better-supabase

## 0.47.0

### Minor Changes

- a change

## 0.46.0

- older
`;

describe("changelogSection", () => {
  it("returns only the requested version", () => {
    expect(changelogSection(changelog, "0.47.0")).toBe(
      "### Minor Changes\n\n- a change",
    );
  });

  it("returns an empty string for an unknown version", () => {
    expect(changelogSection(changelog, "9.9.9")).toBe("");
  });
});

describe("truncateNotes", () => {
  it("keeps a short body as it is", () => {
    expect(truncateNotes("short", "https://example.test")).toBe("short");
  });

  it("cuts a long body under the limit and links the changelog", () => {
    const body = Array.from({ length: 20_000 }, (_, i) => `- line ${i}`).join(
      "\n",
    );

    const notes = truncateNotes(body, "https://example.test/CHANGELOG.md");

    expect(body.length).toBeGreaterThan(MAX_BODY_LENGTH);
    expect(notes.length).toBeLessThanOrEqual(MAX_BODY_LENGTH);
    expect(notes).toContain("(https://example.test/CHANGELOG.md)");
    expect(notes).toMatch(/- line \d+\n\n---/);
  });
});
