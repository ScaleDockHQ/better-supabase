import { describe, expectTypeOf, it } from "vitest";

import type { InvitationDraft } from "../../../src/blocks/organizations/client.ts";
import type { InviteRequest } from "../../../src/blocks/organizations/organizations.ts";
import type { RoleNames } from "../../../src/config/references.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createInvitationsController } from "../../../src/blocks/organizations/client.ts";
import { createOrganizations } from "../../../src/blocks/organizations/organizations.ts";

const config = {
  blocks: { permissions: { roles: { owner: {}, admin: {}, member: {} } } },
} as const;

type Role = RoleNames<typeof config>;

declare const transport: BlockTransport;

describe("invitation roles", () => {
  it("takes the configured roles", () => {
    expectTypeOf<Role>().toEqualTypeOf<"owner" | "admin" | "member">();
    expectTypeOf<
      InviteRequest<Record<never, never>, Role>["role"]
    >().toEqualTypeOf<Role>();
    expectTypeOf<
      NonNullable<InviteRequest<Record<never, never>, Role>["onAccept"]>
    >().toEqualTypeOf<{
      readonly roles?: readonly Role[];
      readonly teams?: readonly string[];
    }>();
  });

  it("rejects an unknown role on invite", () => {
    const organizations = createOrganizations<undefined, undefined, Role>({
      transport,
    });

    void organizations.invite({
      organizationId: "o1",
      email: "a@example.com",
      role: "admin",
      onAccept: { roles: ["member"], teams: ["t1"] },
    });

    void organizations.invite({
      organizationId: "o1",
      email: "a@example.com",
      // @ts-expect-error: not a configured role
      role: "viewer",
    });

    void organizations.invite({
      organizationId: "o1",
      email: "a@example.com",
      role: "member",
      // @ts-expect-error: not a configured role
      onAccept: { roles: ["viewer"] },
    });
  });

  it("keeps string without a role union", () => {
    expectTypeOf<InviteRequest["role"]>().toEqualTypeOf<string>();
    expectTypeOf<InvitationDraft["role"]>().toEqualTypeOf<string>();
    expectTypeOf<RoleNames<{ blocks: {} }>>().toEqualTypeOf<string>();
  });

  it("types the controller's draft", () => {
    const controller = createInvitationsController<
      { readonly id: string },
      Role
    >({
      client: createOrganizations({ transport }),
      auth: undefined as never,
      organizationId: "o1",
      load: async () => [],
    });

    expectTypeOf(controller.actions.invite)
      .parameter(0)
      .toEqualTypeOf<InvitationDraft<Role>>();
  });
});
