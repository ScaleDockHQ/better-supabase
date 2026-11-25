import { describe, expect, it } from "vitest";

import { areaCommands } from "@/features/areas/area-commands";
import { AREAS } from "@/features/areas/areas";
import { navItems } from "@/features/navigation/nav-items";

const allHrefs = navItems.map((item) => item.href);

/** Area steps with no menu entry above them, so the palette leaves them out. */
const UNLISTED_STEPS = new Set(["/settings/webhooks"]);

describe("areaCommands", () => {
  it("lists every area hub, step and action when the whole menu is visible", () => {
    const commands = areaCommands({ visibleHrefs: allHrefs, hubs: true });

    expect(commands.filter((c) => c.kind === "area")).toHaveLength(
      AREAS.length,
    );
    expect(commands.filter((c) => c.kind === "step")).toHaveLength(
      AREAS.flatMap((area) => area.steps).filter(
        (step) => !UNLISTED_STEPS.has(step.route),
      ).length,
    );
    expect(commands.filter((c) => c.kind === "action")).toHaveLength(
      AREAS.flatMap((area) => area.actions).length,
    );
    expect(new Set(commands.map((c) => c.id)).size).toBe(commands.length);
  });

  it("drops the hubs without the Areas menu entry", () => {
    const commands = areaCommands({ visibleHrefs: allHrefs, hubs: false });

    expect(commands.some((c) => c.kind === "area")).toBe(false);
  });

  it("offers only pages under a visible menu entry", () => {
    const commands = areaCommands({ visibleHrefs: ["/drive"], hubs: false });

    expect(commands.length).toBeGreaterThan(0);
    expect(
      commands.every(
        (c) => c.href === "/drive" || c.href.startsWith("/drive/"),
      ),
    ).toBe(true);
    expect(commands.map((c) => c.label)).toContain("Create a public link");
  });

  it("does not treat a shared prefix as a parent route", () => {
    const commands = areaCommands({ visibleHrefs: ["/people"], hubs: false });

    expect(commands.some((c) => c.href === "/people/hiring")).toBe(true);
    expect(commands.some((c) => c.href.startsWith("/peoples"))).toBe(false);
    expect(commands.some((c) => c.href === "/courses")).toBe(false);
  });
});
