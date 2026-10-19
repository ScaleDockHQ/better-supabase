import {
  designIssues,
  EMPTY_DESIGN,
  addTable,
  withDesign,
  previewFiles,
} from "better-supabase/create";
import {
  decodeDesign,
  encodeDesign,
  encodePreset,
  namedPreset,
} from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import {
  createReducer,
  initialCreateState,
  presetOfState,
} from "../../lib/create-state";
import {
  DESIGN_TEMPLATES,
  type DesignTemplate,
  templatePreset,
  templateTables,
} from "../../lib/design-templates";
import { installedBlocks, RECORD_FEATURES } from "../../lib/record-features";
import { presetSchema } from "./schema-fixture";

function templateOf(id: string): DesignTemplate {
  const template = DESIGN_TEMPLATES.find((each) => each.id === id);

  if (template === undefined) {
    throw new Error(`No template ${id}.`);
  }

  return template;
}

describe("design templates", () => {
  test("have unique ids and at least two tables each", () => {
    const ids = DESIGN_TEMPLATES.map((template) => template.id);

    expect(new Set(ids).size).toBe(ids.length);
    expect(DESIGN_TEMPLATES.length).toBeGreaterThanOrEqual(6);

    for (const template of DESIGN_TEMPLATES) {
      expect(templateTables(template).length).toBeGreaterThanOrEqual(2);
    }
  });

  test.each(
    DESIGN_TEMPLATES.map((template) => [template.id, template] as const),
  )("%s renders without issues", async (_id, template) => {
    const preset = templatePreset(namedPreset("minimal"), template);
    const { data } = presetSchema(template.preset, { blocks: preset.blocks });
    const shown = withDesign(data, template.design, preset);

    expect(designIssues(template.design, shown, preset)).toEqual([]);

    const files = previewFiles(encodePreset(preset), template.design);
    const sql = files.map((file) => file.contents).join("\n");

    for (const table of templateTables(template)) {
      expect(sql).toContain(`create table if not exists "public"."${table}"`);
    }

    const needed = Object.values(template.design.appTables ?? {}).flatMap(
      ({ subject }) =>
        RECORD_FEATURES.filter(
          (info) =>
            subject !== undefined &&
            info.key !== undefined &&
            subject[info.key] !== undefined,
        ).map((info) => info.block),
    );

    expect([...installedBlocks(preset)]).toEqual(
      expect.arrayContaining(needed),
    );

    await expect(
      encodeDesign(template.design).then(decodeDesign),
    ).resolves.toEqual(template.design);
  });

  test("adds the blocks a template needs to its named preset", () => {
    const preset = templatePreset(
      namedPreset("minimal"),
      templateOf("content-calendar"),
    );

    expect(preset.blocks).toEqual(
      expect.arrayContaining(["organizations", "tags", "comments"]),
    );
  });

  test("starting from a template is one undo step", () => {
    const template = templateOf("projects-and-tasks");
    const before = addTable(EMPTY_DESIGN, "notes");
    const start = initialCreateState(namedPreset("minimal"), before);

    const started = createReducer(start, {
      type: "template",
      update: (current) => templatePreset(current, template),
      design: template.design,
    });

    expect(started.history.present.design).toBe(template.design);
    expect(presetOfState(started).blocks).toEqual(
      templatePreset(namedPreset("minimal"), template).blocks,
    );

    const undone = createReducer(started, { type: "undo" });

    expect(undone.history.present.design).toBe(before);
    expect(presetOfState(undone).blocks).toEqual(namedPreset("minimal").blocks);
  });
});
