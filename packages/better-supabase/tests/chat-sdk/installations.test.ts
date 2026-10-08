import { describe, expect, it, vi } from "vitest";

import type {
  CredentialProvider,
  CredentialRef,
} from "../../src/credentials/index.ts";

import { createChatInstallations } from "../../src/chat-sdk/index.ts";
import { AsyncResult } from "../../src/core/result.ts";

const AT = "2026-01-01T00:00:00Z";
const ref = (secret: string): CredentialRef => ({ provider: "vault", secret });

const row = (
  credential: CredentialRef | null,
  extra: Record<string, unknown> = {},
) => ({
  id: "inst1",
  tenant_id: "org",
  adapter: "slack",
  external_id: "T1",
  credential_ref: credential,
  installed_by: "u1",
  metadata: { team: "Acme" },
  installed_at: AT,
  uninstalled_at: null,
  ...extra,
});

function provider(): CredentialProvider & { revoke: ReturnType<typeof vi.fn> } {
  return {
    apiVersion: 1,
    name: "fake",
    getToken: () => AsyncResult.ok({ token: "t", headers: {} }),
    capabilities: () => ({
      userSubjects: false,
      authorization: false,
      revoke: true,
      inbound: false,
    }),
    revoke: vi.fn(() => AsyncResult.ok(true)),
  };
}

function setup(answers: Record<string, unknown>) {
  const call = vi.fn(async (_schema: string, fn: string) => answers[fn]);
  const credentials = provider();
  return {
    call,
    credentials,
    installations: createChatInstallations({
      transport: { call },
      credentials,
    }),
  };
}

describe("createChatInstallations", () => {
  it("revokes the ref a reinstall replaces", async () => {
    const { installations, credentials, call } = setup({
      chat_install: row(ref("new"), { previous_credential_ref: ref("old") }),
    });
    const installed = await installations
      .install({
        adapter: "slack",
        externalId: "T1",
        tenant: "org",
        credentialRef: ref("new"),
      })
      .orThrow();
    expect(installed).toMatchObject({
      tenant: "org",
      credentialRef: ref("new"),
      metadata: { team: "Acme" },
      uninstalledAt: null,
    });
    expect(installed.installedAt.toString()).toBe(AT);
    expect(credentials.revoke).toHaveBeenCalledWith(ref("old"), {
      subject: { type: "app" },
    });
    expect(call.mock.calls[0]?.[2]).toMatchObject({
      adapter: "slack",
      external_id: "T1",
    });
  });

  it("keeps a ref the reinstall keeps", async () => {
    const { installations, credentials } = setup({
      chat_install: row(ref("same"), { previous_credential_ref: ref("same") }),
    });
    await installations
      .install({ adapter: "slack", externalId: "T1" })
      .orThrow();
    expect(credentials.revoke).not.toHaveBeenCalled();
  });

  it("fails when the install returns nothing", async () => {
    const { installations } = setup({ chat_install: null });
    const result = await installations.install({
      adapter: "slack",
      externalId: "T1",
    });
    expect(result.ok).toBe(false);
  });

  it("revokes on uninstall", async () => {
    const { installations, credentials } = setup({
      chat_uninstall: { previous_credential_ref: ref("old") },
    });
    expect(await installations.uninstall("slack", "T1").orThrow()).toBe(true);
    expect(credentials.revoke).toHaveBeenCalledTimes(1);
    const none = setup({ chat_uninstall: null });
    expect(await none.installations.uninstall("slack", "T1").orThrow()).toBe(
      false,
    );
  });

  it("uninstalls a tenant's installs", async () => {
    const { installations, credentials } = setup({
      list_chat_installations: [
        row(ref("a")),
        "junk",
        row(null, { external_id: "T2" }),
      ],
      chat_uninstall: { previous_credential_ref: null },
    });
    expect(await installations.uninstallTenant("org").orThrow()).toBe(2);
    expect(credentials.revoke).not.toHaveBeenCalled();
  });

  it("reads installs", async () => {
    const { installations } = setup({
      chat_installation: row(
        { secret: "no provider" },
        { tenant_id: null, uninstalled_at: AT, metadata: null },
      ),
      list_chat_installations: "not a list",
    });
    const found = await installations.get("slack", "T1").orThrow();
    expect(found).toMatchObject({
      tenant: null,
      credentialRef: null,
      metadata: {},
    });
    expect(found?.uninstalledAt?.toString()).toBe(AT);
    expect(
      await installations.list({ includeUninstalled: true }).orThrow(),
    ).toEqual([]);
  });
});
