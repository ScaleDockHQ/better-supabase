import { describe, expect, it } from "vitest";

import { createProfiles } from "../../../src/blocks/profiles/profiles.ts";

function setup(
  uploader?: Parameters<typeof createProfiles>[0]["avatarUploader"],
) {
  const calls: [string, Record<string, unknown>][] = [];

  const profiles = createProfiles({
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push([fn, args]);

        return Promise.resolve(
          fn === "my_profile" ? { id: "u1", avatar_path: "old.png" } : true,
        );
      },
    },
    ...(uploader === undefined ? {} : { avatarUploader: uploader }),
  });

  return { profiles, calls };
}

describe("profiles.setAvatar", () => {
  it("commits a path, or clears it with null", async () => {
    const { profiles, calls } = setup();

    await profiles.setAvatar({ path: "a.png" }).orThrow();
    await profiles.setAvatar({ path: null }).orThrow();

    expect(calls).toEqual([
      ["update_my_profile", { attrs: { avatar_path: "a.png" } }],
      ["update_my_profile", { attrs: { avatar_path: null } }],
    ]);
  });

  it("hands the file, the previous path and a commit to the uploader", async () => {
    const seen: (string | null)[] = [];

    const { profiles, calls } = setup(({ previous, commit }) => {
      seen.push(previous);

      return commit("new.png");
    });

    expect(await profiles.setAvatar({ file: new Blob(["x"]) }).orThrow()).toBe(
      true,
    );
    expect(seen).toEqual(["old.png"]);
    expect(calls.at(-1)).toEqual([
      "update_my_profile",
      { attrs: { avatar_path: "new.png" } },
    ]);
  });

  it("fails without an uploader", async () => {
    const { profiles } = setup();
    const result = await profiles.setAvatar({ file: new Blob(["x"]) });

    expect(!result.ok && result.error.kind).toBe("invalid_request");
  });
});
