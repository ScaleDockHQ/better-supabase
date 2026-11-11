import { describe, expect, it } from "vitest";

import {
  activeNavId,
  navAreas,
  navItems,
} from "@/features/navigation/nav-items";

describe("nav items", () => {
  it("puts every item in a product area and uses every area", () => {
    for (const item of navItems) {
      expect(navAreas).toContain(item.area);
    }

    for (const area of navAreas) {
      expect(navItems.some((item) => item.area === area)).toBe(true);
    }
  });

  it("lists each id once", () => {
    const ids = navItems.map((item) => item.id);

    expect(new Set(ids).size).toBe(ids.length);
  });

  it("marks the deepest matching entry as current", () => {
    expect(activeNavId("/crm/deals")).toBe("deals");
    expect(activeNavId("/assistant/activity")).toBe("agentActivity");
    expect(activeNavId("/assistant/abc")).toBe("assistant");
  });
});
