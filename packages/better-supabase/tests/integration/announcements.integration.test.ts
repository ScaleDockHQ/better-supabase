import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createAnnouncements,
  sqlTransport,
} from "../../src/blocks/announcements/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("announcements", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("shows each user the announcements for their audience until they dismiss them", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "announcements"]);
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { admin, member });
      const other = await s.organization(await s.user("other"));
      const announcements = createAnnouncements({
        transport: sqlTransport(s.sql),
      });

      await s.as(admin);
      expect(
        await announcements
          .publish({ title: "No" })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("ANNOUNCEMENT_FORBIDDEN");

      await s.service();
      const now = Temporal.Now.instant();
      const everyone = await announcements
        .publish({ title: "Everyone", severity: "success" })
        .orThrow();
      const admins = await announcements
        .publish({
          title: "Admins",
          audience: { type: "role", roles: ["admin"] },
          dismissible: false,
        })
        .orThrow();
      const ours = await announcements
        .publish({
          title: "Ours",
          audience: { type: "tenant", organizationIds: [tenant] },
          href: "/billing",
        })
        .orThrow();
      await announcements
        .publish({
          title: "Theirs",
          audience: { type: "tenant", organizationIds: [other] },
        })
        .orThrow();
      await announcements
        .publish({
          title: "Later",
          startsAt: now.add({ hours: 1 }),
        })
        .orThrow();
      const ended = await announcements
        .publish({
          title: "Ended",
          startsAt: now.subtract({ hours: 2 }),
          endsAt: now.subtract({ hours: 1 }),
        })
        .orThrow();
      expect(ours).toMatchObject({
        href: "/billing",
        audience: { type: "tenant", organizationIds: [tenant] },
      });
      expect(
        await announcements
          .publish({ title: "Bad", audience: { type: "plan", plans: ["pro"] } })
          .then((r) => r.ok),
      ).toBe(false);
      expect(
        await announcements
          .publish({ title: "Bad", href: "javascript:alert(1)" })
          .then((r) => r.ok),
      ).toBe(false);

      const titles = async (organizationId?: string) =>
        (await announcements.listActive(organizationId).orThrow())
          .map((a) => a.title)
          .filter((t) =>
            [
              "Everyone",
              "Admins",
              "Admins and members",
              "Ours",
              "Theirs",
            ].includes(t),
          )
          .toSorted();

      await s.as(admin);
      expect(await titles(tenant)).toEqual(["Admins", "Everyone", "Ours"]);
      expect(await titles(other)).toEqual(["Everyone"]);
      expect(await titles()).toEqual(["Everyone"]);
      await s.as(member);
      expect(await titles(tenant)).toEqual(["Everyone", "Ours"]);

      expect(await announcements.dismiss(everyone.id).orThrow()).toBe(true);
      expect(await announcements.dismiss(everyone.id).orThrow()).toBe(false);
      expect(await titles(tenant)).toEqual(["Ours"]);
      await s.as(admin);
      expect(
        await announcements
          .dismiss(admins.id)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("ANNOUNCEMENT_NOT_DISMISSIBLE");
      expect(
        await announcements
          .dismiss(crypto.randomUUID())
          .then((r) => !r.ok && r.error.hint),
      ).toBe("ANNOUNCEMENT_NOT_FOUND");
      expect(await titles(tenant)).toContain("Everyone");

      await s.service();
      const updated = await announcements
        .update(admins.id, {
          title: "Admins and members",
          audience: { type: "role", roles: ["admin", "member"] },
        })
        .orThrow();
      expect(updated).toMatchObject({
        title: "Admins and members",
        dismissible: false,
        createdBy: undefined,
      });
      expect(updated.updatedAt.epochMilliseconds).toBeGreaterThanOrEqual(
        admins.updatedAt.epochMilliseconds,
      );
      expect(
        await announcements
          .update(crypto.randomUUID(), { title: "x" })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("ANNOUNCEMENT_NOT_FOUND");
      const all = await announcements.list().orThrow();
      expect(all.map((a) => a.id)).toContain(ended.id);
      expect(await announcements.remove(ended.id).orThrow()).toBe(true);
      expect(await announcements.remove(ended.id).orThrow()).toBe(false);

      await s.as(member);
      expect(
        await announcements.list().then((r) => !r.ok && r.error.hint),
      ).toBe("ANNOUNCEMENT_FORBIDDEN");
      expect(await titles(tenant)).toEqual(
        ["Admins and members", "Ours"].toSorted(),
      );
      await s.as("anon");
      expect(
        await announcements.dismiss(ours.id).then((r) => !r.ok && r.error.hint),
      ).toBe("ANNOUNCEMENT_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
