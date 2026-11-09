import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/resolve.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const READ_POLICY = /create policy "?bsb_attachments_read"?[\s\S]*?;\n/;

describe("attachments policies over subject tables", () => {
  it("send a subject type no installed block creates through the late-binding function", () => {
    // `tasks` is only installed as the `maintenance` instance, so
    // better_supabase.tasks never exists and an inline check would not install.
    const config = resolveConfig({ preset: "property" }, "/app");

    const attachments = renderBlocks(
      config.blockNames,
      moduleLayout(config),
    ).find((file) => file.path.includes("_attachments"));

    const policy = READ_POLICY.exec(attachments?.contents ?? "")?.[0] ?? "";

    expect(policy).not.toBe("");
    expect(policy).not.toContain('"better_supabase"."tasks"');
    expect(policy).toContain("attachment_subject_readable");
  });
});
