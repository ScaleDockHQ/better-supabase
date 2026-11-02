import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { linksWithoutRelations } from "../../../src/cli/doctor/block-links.ts";
import { PRESET_CATALOG } from "../../../src/preset/index.ts";

const linked = PRESET_CATALOG.blocks.find((block) =>
  (block.links ?? []).some(
    (link) => link.kind === "conversion" || link.kind === "relation",
  ),
);

const link = linked?.links?.find(
  (candidate) =>
    candidate.kind === "conversion" || candidate.kind === "relation",
);

const context = (blocks: Record<string, unknown>): DoctorContext =>
  // SAFETY: BS353 reads only the installed blocks of the config.
  ({ config: { blocks } }) as unknown as DoctorContext;

describe("linksWithoutRelations", () => {
  it("names a link whose lineage is not recorded", () => {
    expect(linked).toBeDefined();

    const findings = linksWithoutRelations(
      context({
        [linked?.name ?? ""]: true,
        [link?.target.block ?? ""]: { block: link?.target.block },
      }),
    );

    expect(findings.map((finding) => finding.target)).toContain(
      `blocks.${linked?.name ?? ""}`,
    );
    expect(findings[0]?.message).toContain("relations is not installed");
  });

  it("stays quiet once relations is installed or no target is", () => {
    expect(
      linksWithoutRelations(
        context({ [linked?.name ?? ""]: true, relations: true }),
      ),
    ).toEqual([]);
    expect(
      linksWithoutRelations(context({ [linked?.name ?? ""]: true })),
    ).toEqual(
      expect.not.arrayContaining([
        expect.objectContaining({ target: `blocks.${link?.key ?? ""}` }),
      ]),
    );
  });
});
