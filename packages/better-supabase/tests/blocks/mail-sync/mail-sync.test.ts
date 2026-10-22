import { describe, expect, it, vi } from "vitest";

import type { MailProvider } from "../../../src/blocks/mail-sync/index.ts";
import type { CredentialProvider } from "../../../src/credentials/provider.ts";

import {
  createMailSync,
  mailAccountInputSchema,
  mailDraftSchema,
  mailSyncBlock,
  messageArg,
} from "../../../src/blocks/mail-sync/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const accountRow = {
  id: "a1",
  tenant_id: "org",
  user_id: "u1",
  provider: "gmail",
  address: "me@acme.test",
  credential_ref: { provider: "vault", tenant: "org", key: "gmail" },
  share: "records",
  status: "active",
  sync_cursor: null,
  last_synced_at: null,
  last_error: null,
  created_at: AT,
};

const threadRow = {
  id: "t1",
  tenant_id: "org",
  account_id: "a1",
  address: "me@acme.test",
  external_id: "gt1",
  subject: "Hi",
  snippet: null,
  last_message_at: AT,
  message_count: 2,
  engagement_id: "e1",
  subjects: [{ type: "person", id: "p1" }],
};

const messageRow = {
  id: "m1",
  thread_id: "t1",
  account_id: "a1",
  external_id: "g1",
  rfc_message_id: "<m1@globex.test>",
  direction: "inbound",
  from_address: "bob@globex.test",
  from_name: "Bob",
  to_addresses: ["me@acme.test"],
  cc_addresses: null,
  subject: "Hi",
  snippet: "Hello",
  body_text: "Hello",
  body_html: null,
  sent_at: AT,
};

const credentials = (): CredentialProvider & {
  getToken: ReturnType<typeof vi.fn>;
} => ({
  apiVersion: 1,
  name: "vault",
  getToken: vi.fn(() =>
    AsyncResult.ok({ token: "t", headers: { authorization: "Bearer t" } }),
  ),
  capabilities: () => ({
    userSubjects: true,
    authorization: false,
    revoke: true,
    inbound: false,
  }),
  revoke: () => AsyncResult.ok(true),
});

function provider(
  overrides: Partial<MailProvider> = {},
): MailProvider & {
  list: ReturnType<typeof vi.fn>;
  send: ReturnType<typeof vi.fn>;
} {
  return {
    apiVersion: 1,
    name: "gmail",
    scopes: ["mail"],
    list: vi.fn(() =>
      AsyncResult.ok({
        messages: [
          {
            externalId: "g2",
            threadId: "gt1",
            to: [{ address: "me@acme.test" }],
            cc: [],
            sentAt: Temporal.Instant.from(AT),
          },
        ],
        cursor: "c2",
        more: false,
      }),
    ),
    send: vi.fn(() =>
      AsyncResult.ok({
        externalId: "s1",
        threadId: "gt1",
        messageId: "<s1@acme.test>",
      }),
    ),
    ...overrides,
    // SAFETY: the mocks above implement both methods; overrides replace them.
  } as MailProvider & {
    list: ReturnType<typeof vi.fn>;
    send: ReturnType<typeof vi.fn>;
  };
}

const answers = {
  connect_mail_account: accountRow,
  update_mail_account: { ...accountRow, share: "private", status: "paused" },
  disconnect_mail_account: true,
  mail_accounts_of: [
    accountRow,
    {
      ...accountRow,
      id: "a2",
      status: "error",
      last_error: "boom",
      sync_cursor: "c1",
      last_synced_at: AT,
    },
    { ...accountRow, id: "a3", status: "disconnected" },
  ],
  list_mail_threads: [threadRow],
  mail_threads_of: [{ ...threadRow, subjects: null, engagement_id: null }],
  get_mail_thread: (args: Record<string, unknown>) =>
    args["thread"] === "t1"
      ? {
          ...threadRow,
          messages: [
            messageRow,
            {
              ...messageRow,
              id: "m2",
              from_name: null,
              rfc_message_id: null,
              direction: "outbound",
            },
          ],
        }
      : args["thread"] === "empty"
        ? { ...threadRow, messages: [] }
        : null,
  link_mail_thread: threadRow,
  unlink_mail_thread: true,
  get_mail_account: (args: Record<string, unknown>) =>
    args["account"] === "a1"
      ? accountRow
      : args["account"] === "gone"
        ? { ...accountRow, status: "disconnected" }
        : args["account"] === "outlook"
          ? { ...accountRow, provider: "outlook" }
          : args["account"] === "foreign"
            ? {
                ...accountRow,
                credential_ref: { provider: "vault", tenant: "x" },
              }
            : null,
  record_sent_mail: { ...messageRow, id: "m3", direction: "outbound" },
  ingest_mail: { stored: 1, threads: 1 },
  due_mail_accounts: [
    accountRow,
    { ...accountRow, id: "a2", provider: "outlook" },
  ],
  set_mail_account_status: true,
};

describe("createMailSync", () => {
  it("manages mailboxes and reads threads", async () => {
    const { transport, call } = fakeTransport(answers);
    const mail = createMailSync({ transport });

    const account = await mail
      .connect("org", {
        provider: "gmail",
        address: "me@acme.test",
        credentialRef: accountRow.credential_ref,
      })
      .orThrow();

    expect(account).toMatchObject({
      id: "a1",
      organizationId: "org",
      userId: "u1",
      share: "records",
      status: "active",
    });
    expect(account.cursor).toBeUndefined();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "connect_mail_account",
      expect.objectContaining({ share: null }),
    );

    await mail
      .connect("org", {
        provider: "gmail",
        address: "me@acme.test",
        credentialRef: accountRow.credential_ref,
        share: "private",
      })
      .orThrow();
    expect(
      await mail.update("a1", { share: "private", paused: true }).orThrow(),
    ).toMatchObject({ share: "private", status: "paused" });
    await mail.update("a1", {}).orThrow();
    expect(await mail.disconnect("a1").orThrow()).toBe(true);
    await mail.disconnect("a1", { purge: true }).orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "disconnect_mail_account",
      { account: "a1", purge: true },
    );

    const accounts = await mail.accounts("org").orThrow();

    expect(accounts.map((entry) => entry.status)).toEqual([
      "active",
      "error",
      "disconnected",
    ]);
    expect(accounts[1]).toMatchObject({ cursor: "c1", lastError: "boom" });

    const threads = await mail.threads("org").orThrow();

    expect(threads[0]).toMatchObject({
      id: "t1",
      address: "me@acme.test",
      messageCount: 2,
      engagementId: "e1",
      subjects: [{ type: "person", id: "p1" }],
    });
    await mail
      .threads("org", {
        accountId: "a1",
        before: Temporal.Instant.from(AT),
        limit: 5,
      })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_mail_threads",
      { tenant: "org", account: "a1", before: AT, page_size: 5 },
    );

    const of = await mail.threadsOf({ type: "person", id: "p1" }).orThrow();

    expect(of[0]?.subjects).toEqual([]);
    expect(of[0]?.engagementId).toBeUndefined();
    await mail
      .threadsOf(
        { type: "person", id: "p1" },
        { before: Temporal.Instant.from(AT), limit: 2 },
      )
      .orThrow();

    const detail = await mail.thread("t1").orThrow();

    expect(detail?.messages[0]).toMatchObject({
      messageId: "<m1@globex.test>",
      from: { address: "bob@globex.test", name: "Bob" },
      to: ["me@acme.test"],
      cc: [],
      text: "Hello",
    });
    expect(detail?.messages[1]).toMatchObject({
      direction: "outbound",
      from: { address: "bob@globex.test" },
    });
    expect(detail?.messages[1]?.from?.name).toBeUndefined();
    expect(await mail.thread("nope").orThrow()).toBeUndefined();

    expect(
      (await mail.link("t1", [{ type: "person", id: "p1" }]).orThrow()).id,
    ).toBe("t1");
    expect(
      await mail.unlink("t1", { type: "person", id: "p1" }).orThrow(),
    ).toBe(true);
  });

  it("refuses a row it can't read", async () => {
    const { transport } = fakeTransport({
      ...answers,
      connect_mail_account: { ...accountRow, share: "everyone" },
      mail_accounts_of: [{ ...accountRow, credential_ref: null }],
    });

    const mail = createMailSync({ transport });

    const connected = await mail.connect("org", {
      provider: "gmail",
      address: "me@acme.test",
      credentialRef: accountRow.credential_ref,
    });

    expect(connected.ok).toBe(false);
    expect((await mail.accounts("org")).ok).toBe(false);
  });

  it("sends through the provider and stores the message", async () => {
    const { transport, call } = fakeTransport(answers);
    const creds = credentials();
    const gmail = provider();

    const mail = createMailSync({
      transport,
      credentials: creds,
      providers: [gmail],
    });

    const sent = await mail
      .send("a1", {
        to: [{ address: "bob@globex.test" }],
        subject: "Re: Hi",
        text: "Thanks",
        html: "<p>Thanks</p>",
        threadId: "t1",
      })
      .orThrow();

    expect(sent.id).toBe("m3");
    expect(creds.getToken).toHaveBeenCalledWith(accountRow.credential_ref, {
      subject: { type: "user", id: "u1" },
      scopes: ["mail"],
    });
    expect(gmail.send).toHaveBeenCalledWith(
      expect.objectContaining({
        from: { address: "me@acme.test" },
        reply: { threadId: "gt1", externalId: "g1" },
        draft: expect.not.objectContaining({ threadId: "t1" }),
      }),
    );
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_sent_mail",
      {
        account: "a1",
        message: expect.objectContaining({
          externalId: "s1",
          threadId: "gt1",
          messageId: "<s1@acme.test>",
          direction: "outbound",
          snippet: "Thanks",
          html: "<p>Thanks</p>",
        }),
      },
    );

    await mail
      .send("a1", { to: [{ address: "bob@globex.test" }], subject: "New" })
      .orThrow();
    expect(gmail.send).toHaveBeenLastCalledWith(
      expect.not.objectContaining({ reply: expect.anything() }),
    );
  });

  it("replies to the latest message with its id", async () => {
    const { transport } = fakeTransport({
      ...answers,
      get_mail_thread: { ...threadRow, messages: [messageRow] },
    });

    const gmail = provider({
      send: vi.fn(() => AsyncResult.ok({ externalId: "s2", threadId: "gt1" })),
    });

    const mail = createMailSync({
      transport,
      credentials: credentials(),
      providers: [gmail],
    });

    await mail.send("a1", { to: [], subject: "Re", threadId: "t1" }).orThrow();

    expect(gmail.send).toHaveBeenCalledWith(
      expect.objectContaining({
        reply: {
          threadId: "gt1",
          externalId: "g1",
          messageId: "<m1@globex.test>",
        },
      }),
    );
  });

  it("returns why a send can't go out", async () => {
    const { transport } = fakeTransport(answers);
    const draft = { to: [{ address: "bob@globex.test" }], subject: "Hi" };

    const failing = provider({
      send: vi.fn(() => AsyncResult.err(dbError("unauthorized", "refused"))),
    });

    const ready = createMailSync({
      transport,
      credentials: credentials(),
      providers: [failing],
    });

    const kind = async (result: AsyncResult<unknown>) => {
      const settled = await result;

      return settled.ok
        ? undefined
        : (settled.error.hint ?? settled.error.kind);
    };

    expect(await kind(ready.send("missing", draft))).toBe(
      "MAIL_ACCOUNT_NOT_FOUND",
    );
    expect(await kind(ready.send("gone", draft))).toBe(
      "MAIL_ACCOUNT_NOT_FOUND",
    );
    expect(await kind(ready.send("outlook", draft))).toBe(
      "MAIL_PROVIDER_MISSING",
    );
    expect(await kind(ready.send("foreign", draft))).toBe(
      "CREDENTIAL_REF_FOREIGN",
    );
    expect(await kind(ready.send("a1", { ...draft, threadId: "nope" }))).toBe(
      "MAIL_THREAD_NOT_FOUND",
    );
    expect(await kind(ready.send("a1", { ...draft, threadId: "empty" }))).toBe(
      "MAIL_THREAD_NOT_FOUND",
    );
    expect(await kind(ready.send("a1", draft))).toBe("unauthorized");

    const bare = createMailSync({ transport, providers: [provider()] });

    expect(await kind(bare.send("a1", draft))).toBe("MAIL_CREDENTIALS_MISSING");

    const refusing = credentials();
    refusing.getToken.mockReturnValue(
      AsyncResult.err(dbError("not_found", "no grant")),
    );

    expect(
      await kind(
        createMailSync({
          transport,
          credentials: refusing,
          providers: [provider()],
        }).send("a1", draft),
      ),
    ).toBe("not_found");
  });

  it("syncs a mailbox page by page", async () => {
    const { transport, call } = fakeTransport(answers);
    const { scopes: _scopes, ...gmail } = provider();
    gmail.list
      .mockReturnValueOnce(
        AsyncResult.ok({ messages: [], cursor: "c1", more: true }),
      )
      .mockReturnValueOnce(
        AsyncResult.ok({ messages: [], cursor: "c2", more: true }),
      );
    const creds = credentials();

    const mail = createMailSync({
      transport,
      credentials: creds,
      providers: [gmail],
    });

    const account = await mail
      .connect("org", {
        provider: "gmail",
        address: "me@acme.test",
        credentialRef: accountRow.credential_ref,
      })
      .orThrow();

    expect(await mail.sync(account, { pages: 2, limit: 10 }).orThrow()).toBe(2);
    expect(gmail.list).toHaveBeenNthCalledWith(1, {
      token: { token: "t", headers: { authorization: "Bearer t" } },
      limit: 10,
    });
    expect(gmail.list).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ cursor: "c1" }),
    );
    expect(creds.getToken).toHaveBeenCalledWith(accountRow.credential_ref, {
      subject: { type: "user", id: "u1" },
    });
    expect(call).toHaveBeenLastCalledWith("better_supabase", "ingest_mail", {
      account: "a1",
      messages: [],
      next_cursor: "c2",
    });

    expect(await mail.sync({ ...account, cursor: "c9" }).orThrow()).toBe(1);
    expect(gmail.list).toHaveBeenLastCalledWith(
      expect.objectContaining({ cursor: "c9", limit: 50 }),
    );
  });

  it("stops a sync on the first error", async () => {
    const failingIngest = fakeTransport({
      ...answers,
      ingest_mail: () => {
        throw new Error("down");
      },
    });

    const listFails = provider({
      list: vi.fn(() => AsyncResult.err(dbError("network", "down"))),
    });

    const account = {
      id: "a1",
      organizationId: "org",
      userId: "u1",
      provider: "gmail",
      address: "me@acme.test",
      credentialRef: accountRow.credential_ref,
      share: "records" as const,
      status: "active" as const,
      createdAt: Temporal.Instant.from(AT),
    };

    const ingest = await createMailSync({
      transport: failingIngest.transport,
      credentials: credentials(),
      providers: [provider()],
    }).sync(account);

    const list = await createMailSync({
      transport: failingIngest.transport,
      credentials: credentials(),
      providers: [listFails],
    }).sync(account);

    const unknown = await createMailSync({
      transport: failingIngest.transport,
      credentials: credentials(),
    }).sync(account);

    const tokenless = await createMailSync({
      transport: failingIngest.transport,
      providers: [provider()],
    }).sync(account);

    expect(ingest.ok).toBe(false);
    expect(!list.ok && list.error.kind).toBe("network");
    expect(!unknown.ok && unknown.error.hint).toBe("MAIL_PROVIDER_MISSING");
    expect(!tokenless.ok && tokenless.error.hint).toBe(
      "MAIL_CREDENTIALS_MISSING",
    );
  });

  it("syncs the due mailboxes and marks the failing ones", async () => {
    const { transport, call } = fakeTransport(answers);

    const limited = provider({
      name: "outlook",
      list: vi.fn(() =>
        AsyncResult.err(
          dbError("rate_limited", "slow down", { retryAfter: 5 }),
        ),
      ),
    });

    const mail = createMailSync({
      transport,
      credentials: credentials(),
      providers: [provider(), limited],
    });

    const report = await mail
      .syncDue({ accounts: 5, staleAfter: "1 minute", pages: 1, limit: 5 })
      .orThrow();

    expect(report).toEqual({
      accounts: 2,
      stored: 1,
      failed: [{ accountId: "a2", message: "slow down" }],
    });
    expect(call).toHaveBeenCalledWith("better_supabase", "due_mail_accounts", {
      max_count: 5,
      stale_after: "1 minute",
    });
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "set_mail_account_status",
      { account: "a2", status: "active", error: "slow down" },
    );

    const broken = createMailSync({
      transport,
      credentials: credentials(),
      providers: [provider()],
    });

    expect((await broken.syncDue().orThrow()).failed).toEqual([
      { accountId: "a2", message: 'createMailSync has no provider "outlook"' },
    ]);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "set_mail_account_status",
      expect.objectContaining({ status: "error" }),
    );
    expect(call).toHaveBeenCalledWith("better_supabase", "due_mail_accounts", {
      max_count: null,
      stale_after: null,
    });

    const unmarked = fakeTransport({
      ...answers,
      set_mail_account_status: () => {
        throw new Error("down");
      },
    });

    expect(
      (
        await createMailSync({
          transport: unmarked.transport,
          credentials: credentials(),
          providers: [provider()],
        }).syncDue()
      ).ok,
    ).toBe(false);
  });

  it("serializes provider messages", () => {
    expect(
      messageArg({
        externalId: "g1",
        threadId: "t1",
        to: [],
        cc: [],
        sentAt: Temporal.Instant.from(AT),
      }),
    ).toEqual({ externalId: "g1", threadId: "t1", sentAt: AT, to: [], cc: [] });
  });

  it("describes the block", async () => {
    expect(mailSyncBlock).toMatchObject({
      name: "mail-sync",
      sql: ["mail-sync"],
      category: "crm",
    });
    expect(
      (
        await mailAccountInputSchema["~standard"].validate({
          provider: "gmail",
          address: "me@acme.test",
          credentialRef: { provider: "vault" },
        })
      ).issues,
    ).toBeUndefined();
    expect(
      (await mailDraftSchema["~standard"].validate({ subject: "Hi" })).issues,
    ).toBeDefined();
  });
});
