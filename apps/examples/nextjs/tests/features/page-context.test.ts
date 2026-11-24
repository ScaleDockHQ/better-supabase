import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  PageContextBody,
  pageContextOf,
  pageContextOfBody,
} from "@/features/assistant/page-context";

const ID = "00000000-0000-4000-8000-0000000000d1";

describe("pageContextOf", () => {
  it("names the record on a record page", () => {
    expect(pageContextOf(`/crm/deals/${ID}`)).toEqual({
      path: `/crm/deals/${ID}`,
      recordType: "deal",
      recordId: ID,
    });
    expect(pageContextOf(`/assistant/agents/${ID}`).recordType).toBe("agent");
    expect(pageContextOf(`/cases/${ID}`).recordType).toBe("case");
  });

  it("keeps only the path on a list or a page with another segment", () => {
    expect(pageContextOf("/crm/deals")).toEqual({ path: "/crm/deals" });
    expect(pageContextOf("/assistant/agents/runs")).toEqual({
      path: "/assistant/agents/runs",
    });
  });
});

describe("pageContextOfBody", () => {
  it("accepts a valid context and drops a forged one", () => {
    const ok = pageContextOf(`/crm/contracts/${ID}`);

    expect(
      pageContextOfBody(v.safeParse(PageContextBody, { pageContext: ok })),
    ).toEqual(ok);
    expect(
      pageContextOfBody(
        v.safeParse(PageContextBody, {
          pageContext: {
            path: "/x",
            recordType: "deal",
            recordId: "not-a-uuid",
          },
        }),
      ),
    ).toBeUndefined();
    expect(pageContextOfBody(undefined)).toBeUndefined();
  });
});
