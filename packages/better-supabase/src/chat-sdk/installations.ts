import type { BlockTransport } from "../core/block-transport.ts";
import type { ErrorMapper } from "../core/errors.ts";
import type { AsyncResult } from "../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "../credentials/provider.ts";

import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  isRecord,
  optionalText,
  run,
  textOf,
  toInstant,
} from "../core/block-helpers.ts";

/** A workspace, page or number a bot is installed in. */
export interface ChatInstallation {
  readonly id: string;
  readonly tenant: string | null;
  readonly adapter: string;
  readonly externalId: string;
  readonly credentialRef: CredentialRef | null;
  readonly installedBy: string | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly installedAt: Temporal.Instant;
  readonly uninstalledAt: Temporal.Instant | null;
}

export interface InstallInput {
  readonly adapter: string;
  readonly externalId: string;
  readonly tenant?: string;
  readonly credentialRef?: CredentialRef;
  readonly installedBy?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface ChatInstallationsOptions {
  /** `sqlTransport(postgres.asService())` or `rpcTransport` with the service role key. */
  readonly transport: BlockTransport;
  /** Revokes the ref a reinstall replaces and the ref an uninstall clears. */
  readonly credentials: CredentialProvider;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface ChatInstallations {
  /** Records an install; a reinstall revokes the credential it replaces. */
  install(input: InstallInput): AsyncResult<ChatInstallation>;
  /** Marks the install removed and revokes its credential; false when none was live. */
  uninstall(adapter: string, externalId: string): AsyncResult<boolean>;
  /** Uninstalls every live install of a tenant before it is purged; returns how many. */
  uninstallTenant(tenant: string): AsyncResult<number>;
  get(
    adapter: string,
    externalId: string,
  ): AsyncResult<ChatInstallation | null>;
  list(filter?: {
    readonly tenant?: string;
    readonly adapter?: string;
    readonly includeUninstalled?: boolean;
  }): AsyncResult<readonly ChatInstallation[]>;
}

function refOf(value: unknown): CredentialRef | null {
  return isRecord(value) && typeof value["provider"] === "string"
    ? { ...value, provider: value["provider"] }
    : null;
}

function installationOf(value: unknown): ChatInstallation | null {
  if (!isRecord(value)) return null;
  const metadata = value["metadata"];
  const uninstalled = optionalText(value["uninstalled_at"]);
  return {
    id: textOf(value["id"]),
    tenant: optionalText(value["tenant_id"]) ?? null,
    adapter: textOf(value["adapter"]),
    externalId: textOf(value["external_id"]),
    credentialRef: refOf(value["credential_ref"]),
    installedBy: optionalText(value["installed_by"]) ?? null,
    metadata: isRecord(metadata) ? metadata : {},
    installedAt: toInstant(textOf(value["installed_at"])),
    uninstalledAt: uninstalled === undefined ? null : toInstant(uninstalled),
  };
}

const APP: CredentialSubject = { type: "app" };

const sameRef = (a: CredentialRef | null, b: CredentialRef | null): boolean =>
  JSON.stringify(a) === JSON.stringify(b);

/**
 * The `chat_installations` registry with the credential lifecycle: every
 * ref an install drops is revoked through the `CredentialProvider`.
 */
export function createChatInstallations(
  options: ChatInstallationsOptions,
): ChatInstallations {
  const call = blockCall(
    options.transport,
    options.schema ?? DEFAULT_BLOCK_SCHEMA,
    options.mappers,
  );
  const revoke = async (ref: CredentialRef | null): Promise<void> => {
    if (ref) await options.credentials.revoke(ref, { subject: APP }).orThrow();
  };

  const list: ChatInstallations["list"] = (filter = {}) =>
    call(
      "list_chat_installations",
      {
        tenant: filter.tenant,
        adapter: filter.adapter,
        include_uninstalled: filter.includeUninstalled,
      },
      (value) =>
        Array.isArray(value)
          ? value.flatMap((row) => {
              const parsed = installationOf(row);
              return parsed ? [parsed] : [];
            })
          : [],
    );
  const uninstall: ChatInstallations["uninstall"] = (adapter, externalId) =>
    call(
      "chat_uninstall",
      { adapter, external_id: externalId },
      async (value) => {
        if (!isRecord(value)) return false;
        await revoke(refOf(value["previous_credential_ref"]));
        return true;
      },
    );

  return {
    install: (input) =>
      call(
        "chat_install",
        {
          adapter: input.adapter,
          external_id: input.externalId,
          tenant: input.tenant,
          credential_ref: input.credentialRef,
          installed_by: input.installedBy,
          metadata: input.metadata,
        },
        async (value) => {
          const row = installationOf(value);
          if (!row) throw new Error("chat_install returned no row");
          const previous = isRecord(value)
            ? refOf(value["previous_credential_ref"])
            : null;
          if (!sameRef(previous, row.credentialRef)) await revoke(previous);
          return row;
        },
      ),
    uninstall,
    uninstallTenant: (tenant) =>
      run(async () => {
        const rows = await list({ tenant }).orThrow();
        let count = 0;
        for (const row of rows)
          if (await uninstall(row.adapter, row.externalId).orThrow())
            count += 1;
        return count;
      }),
    get: (adapter, externalId) =>
      call(
        "chat_installation",
        { adapter, external_id: externalId },
        installationOf,
      ),
    list,
  };
}
