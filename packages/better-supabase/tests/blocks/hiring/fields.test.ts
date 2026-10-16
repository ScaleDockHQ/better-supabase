import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createHiring } from "../../../src/blocks/hiring/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const JOB = {
  id: "j1",
  title: "Engineer",
  status: "draft",
  fields: { level: 3 },
};

describe("hiring fields", () => {
  it("sends the job's extra fields under fields and parses them back", async () => {
    const t = fieldsTransport({ save_job: () => JOB });
    const hiring = createHiring({
      transport: t,
      fields: v.object({ level: v.number() }),
    });
    const job = await hiring
      .saveJob("o", { title: "Engineer", fields: { level: 3 } })
      .orThrow();
    expect(job.fields.level).toBe(3);
    expect(t.calls[0]?.[1]).toMatchObject({
      attrs: { title: "Engineer", fields: { level: 3 } },
    });
  });

  it("refuses a bad field before the call", async () => {
    const t = fieldsTransport({ save_job: () => JOB });
    const hiring = createHiring({
      transport: t,
      fields: v.object({ level: v.number() }),
    });
    const saved = await hiring.saveJob("o", {
      title: "Engineer",
      fields: { level: "high" as never },
    });
    expect(saved.ok).toBe(false);
    expect(saved.ok ? undefined : saved.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
  });

  it("returns empty fields without extra columns", async () => {
    const t = fieldsTransport({ save_job: () => ({ ...JOB, fields: null }) });
    const job = await createHiring({ transport: t })
      .saveJob("o", { title: "Engineer" })
      .orThrow();
    expect(job.fields).toEqual({});
    expect(t.calls[0]?.[1]["attrs"]).toEqual({ title: "Engineer" });
  });
});
