import { describe, expect, it } from "vitest";

import {
  channelChangeSchema,
  channelInputSchema,
  createChannels,
} from "../../../src/blocks/channels/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const channelRow = {
  id: "c1",
  tenant_id: "org",
  name: "general",
  visibility: "public",
  topic: "Everything",
  purpose: null,
  subject_type: "customer",
  subject_id: "cu1",
  created_by: "u1",
  created_at: AT,
  updated_at: AT,
  role: "owner",
  memberCount: 3,
  lastMessageAt: AT,
  archivedAt: null,
};

const answers = {
  create_channel: channelRow,
  update_channel: { ...channelRow, topic: null },
  archive_channel: true,
  join_channel: true,
  leave_channel: false,
  invite_to_channel: 2,
  list_channels: [channelRow],
  get_channel: (args: Record<string, unknown>) =>
    args["channel"] === "c1" ? channelRow : null,
  find_channel: null,
  channels_for_record: [channelRow],
};

describe("createChannels", () => {
  it("calls every function with snake_case arguments", async () => {
    const { transport, call } = fakeTransport(answers);
    const channels = createChannels({ transport, tenant: "org" });

    const created = await channels
      .create({
        name: "general",
        visibility: "public",
        topic: "Everything",
        purpose: "News",
        subject: { type: "customer", id: "cu1" },
        memberIds: ["u2"],
      })
      .orThrow();

    expect(created).toMatchObject({
      id: "c1",
      organizationId: "org",
      name: "general",
      visibility: "public",
      topic: "Everything",
      purpose: undefined,
      subject: { type: "customer", id: "cu1" },
      role: "owner",
      memberCount: 3,
      archivedAt: undefined,
    });
    expect(created.lastMessageAt?.equals(Temporal.Instant.from(AT))).toBe(true);

    await channels.create({ name: "plain" }).orThrow();
    expect(
      (await channels.update("c1", { topic: null }).orThrow()).topic,
    ).toBeUndefined();
    expect(await channels.archive("c1").orThrow()).toBe(true);
    await channels.archive("c1", false).orThrow();
    expect(await channels.join("c1").orThrow()).toBe(true);
    expect(await channels.leave("c1").orThrow()).toBe(false);
    expect(await channels.invite("c1", ["u2", "u3"]).orThrow()).toBe(2);
    expect(await channels.list().orThrow()).toHaveLength(1);
    await channels.list({ browse: true, includeArchived: true }).orThrow();
    expect((await channels.get("c1").orThrow())?.name).toBe("general");
    expect(await channels.get("nope").orThrow()).toBeUndefined();
    expect(await channels.find("General").orThrow()).toBeUndefined();
    expect(
      await channels.forSubject({ type: "customer", id: "cu1" }).orThrow(),
    ).toHaveLength(1);

    expect(call.mock.calls.map(([, fn, args]) => [fn, args])).toMatchSnapshot();
  });

  it("needs a tenant for the calls that take none", async () => {
    const { transport } = fakeTransport(answers);
    const channels = createChannels({ transport });

    expect((await channels.list()).ok).toBe(false);
    expect((await channels.create({ name: "x" })).ok).toBe(false);
    expect((await channels.find("x")).ok).toBe(false);
    expect(await channels.join("c1").orThrow()).toBe(true);
  });

  it("reads sparse rows and rejects unknown values", async () => {
    const { transport } = fakeTransport({
      ...answers,
      get_channel: {
        ...channelRow,
        subject_type: null,
        subject_id: null,
        role: null,
        memberCount: "many",
      },
      find_channel: { ...channelRow, visibility: "secret" },
    });

    const channels = createChannels({ transport, tenant: "org" });
    const channel = await channels.get("c1").orThrow();

    expect(channel).toMatchObject({
      subject: undefined,
      role: undefined,
      memberCount: 0,
    });
    expect((await channels.find("general")).ok).toBe(false);
  });

  it("runs hooks", async () => {
    const seen: string[] = [];
    const { transport } = fakeTransport(answers);

    const channels = createChannels({
      transport,
      tenant: "org",
      logger: { debug() {}, info() {}, warn() {}, error() {} },
      hooks: {
        join: {
          before: (_args, { method }) => {
            seen.push(method);
          },
        },
      },
    });

    await channels.join("c1").orThrow();
    expect(seen).toEqual(["join"]);
  });
});

describe("channel schemas", () => {
  it("validate what create and update take", async () => {
    const created = await channelInputSchema["~standard"].validate({
      name: "general",
      visibility: "private",
    });

    const changed = await channelChangeSchema["~standard"].validate({
      topic: null,
      visibility: "hidden",
    });

    expect(created.issues).toBeUndefined();
    expect(changed.issues).toBeDefined();
  });
});
