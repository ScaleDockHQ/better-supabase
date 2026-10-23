import { describe, expect, it } from "vitest";

import type { Signer } from "../../../src/blocks/signing-keys/signing-keys.ts";

import {
  createAdmissionPasses,
  PASS_TOKEN_TYPE,
  admissionPassesBlock,
  admissionPassesBinding,
  passInputSchema,
  passSectionInputSchema,
} from "../../../src/blocks/admission-passes/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import {
  generateSigningKey,
  importSigningKey,
  signCompact,
} from "../../../src/core/jws.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";

const AT = "2026-10-22T10:00:00Z";
const LATER = "2026-10-22T12:00:00Z";

const PASS = {
  id: "p1",
  organizationId: "org-1",
  kind: "ticket",
  holderUserId: "u2",
  holderName: "Jane",
  holderEmail: "jane@example.test",
  subjectType: "event",
  subjectId: "e1",
  bookingId: "b1",
  resourceId: "r1",
  usesAllowed: 1,
  uses: 0,
  validFrom: AT,
  validUntil: LATER,
  status: "active",
  issuedBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  revokedAt: null,
  nonce: "n0nce",
};

const BARE_PASS = {
  ...PASS,
  id: "p2",
  kind: "visitor",
  holderUserId: null,
  holderName: null,
  holderEmail: null,
  subjectType: null,
  subjectId: null,
  bookingId: null,
  resourceId: null,
  usesAllowed: null,
  validUntil: null,
  issuedBy: null,
};

const CHECK_IN = {
  id: "c1",
  organizationId: "org-1",
  passId: "p1",
  resourceId: "r1",
  bookingId: "b1",
  gate: "north",
  method: "qr",
  admitted: false,
  reason: "used_up",
  checkedInBy: "u1",
  createdAt: AT,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

async function keys() {
  const pair = await generateSigningKey("Ed25519");
  const key = await importSigningKey(pair.privateKey);

  const sign = (
    claims: Readonly<Record<string, unknown>>,
    header: Readonly<Record<string, unknown>> = {},
  ): Promise<string> =>
    signCompact(
      key,
      "Ed25519",
      { alg: "EdDSA", kid: pair.kid, typ: "JWT", ...header },
      claims,
    );

  const signer: Signer = {
    owner: { type: "organization", id: "org-1" },
    sign: () => AsyncResult.err(dbError("unexpected", "not used")),
    signJwt: (claims, header) =>
      AsyncResult.from(async () => ok(await sign(claims, header))),
  };

  return {
    signer,
    sign,
    jwks: { keys: [{ ...pair.publicKey, kid: pair.kid }] },
  };
}

const seconds = (iso: string): number => Date.parse(iso) / 1000;

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createAdmissionPasses", () => {
  it("books a class with a credit and reads the credit ledger", async () => {
    const fake = fakeTransport({
      book_with_credit: {
        id: "b2",
        resourceId: "r1",
        serviceId: "s1",
        seat: 1,
        startsAt: AT,
        endsAt: LATER,
        status: "confirmed",
        customerUserId: "u2",
        passId: "p1",
        creditsLeft: 4,
      },
      list_pass_credits: [
        {
          id: "e2",
          organizationId: "org-1",
          passId: "p1",
          bookingId: "b2",
          delta: 1,
          reason: "refund",
          createdBy: null,
          createdAt: LATER,
        },
        {
          id: "e1",
          organizationId: "org-1",
          passId: "p1",
          bookingId: "b2",
          delta: -1,
          reason: "booking",
          createdBy: "u2",
          createdAt: AT,
        },
      ],
    });

    const passes = createAdmissionPasses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const booked = await passes
      .bookWithCredit("p1", {
        serviceId: "s1",
        resourceId: "r1",
        startsAt: Temporal.Instant.from(AT),
        customer: { name: "Jane" },
      })
      .orThrow();

    expect(booked).toMatchObject({
      id: "b2",
      status: "confirmed",
      passId: "p1",
      creditsLeft: 4,
    });
    expect(booked.startsAt.toString()).toBe(AT);

    const entries = await passes.credits("p1").orThrow();
    expect(entries.map((entry) => [entry.reason, entry.delta])).toEqual([
      ["refund", 1],
      ["booking", -1],
    ]);
    expect(entries[0]).not.toHaveProperty("createdBy");
    expect(entries[1]).toMatchObject({ bookingId: "b2", createdBy: "u2" });
    expect(fake.calls).toEqual([
      [
        "book_with_credit",
        {
          pass_id: "p1",
          service: "s1",
          resource: "r1",
          starts_at: AT,
          customer: { name: "Jane" },
        },
      ],
      ["list_pass_credits", { pass_id: "p1" }],
    ]);
  });

  it("issues a ticket for a booking in the block's tenant", async () => {
    const fake = fakeTransport({ issue_pass: PASS });

    const passes = createAdmissionPasses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const pass = await passes
      .issue({
        bookingId: "b1",
        holderUserId: "u2",
        holderName: "Jane",
        subject: { type: "event", id: "e1" },
        validUntil: Temporal.Instant.from(LATER),
      })
      .orThrow();

    expect(fake.calls).toEqual([
      [
        "issue_pass",
        {
          tenant: "org-1",
          kind: "ticket",
          holder_user: "u2",
          holder_name: "Jane",
          holder_email: null,
          subject_type: "event",
          subject_id: "e1",
          booking_id: "b1",
          resource_id: null,
          uses_allowed: null,
          valid_from: undefined,
          valid_until: LATER,
        },
      ],
    ]);
    expect(pass).toMatchObject({
      id: "p1",
      nonce: "n0nce",
      subject: { type: "event", id: "e1" },
      usesAllowed: 1,
      status: "active",
    });
    expect(pass.validUntil?.toString()).toBe(LATER);
  });

  it("leaves out what a bare pass doesn't have", async () => {
    const fake = fakeTransport({ revoke_pass: BARE_PASS });
    const passes = createAdmissionPasses({ transport: fake.transport });

    const pass = await passes.revoke("p2").orThrow();

    expect(fake.calls).toEqual([["revoke_pass", { pass_id: "p2" }]]);
    expect(Object.keys(pass).toSorted()).toEqual([
      "createdAt",
      "id",
      "kind",
      "organizationId",
      "status",
      "updatedAt",
      "uses",
      "validFrom",
    ]);
  });

  it("fails without a tenant", async () => {
    const passes = createAdmissionPasses({
      transport: fakeTransport({}).transport,
    });

    expect((await passes.issue({ resourceId: "r1" })).ok).toBe(false);
  });

  it("lists by holder, record and status", async () => {
    const fake = fakeTransport({ list_passes: [PASS, BARE_PASS] });

    const passes = createAdmissionPasses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const list = await passes
      .list({
        holderUserId: "u2",
        subject: { type: "event", id: "e1" },
        status: "active",
        before: Temporal.Instant.from(AT),
        pageSize: 10,
      })
      .orThrow();

    expect(list.map((pass) => pass.id)).toEqual(["p1", "p2"]);
    expect(fake.calls[0]).toEqual([
      "list_passes",
      {
        tenant: "org-1",
        holder_user: "u2",
        subject_type: "event",
        subject_id: "e1",
        status: "active",
        before: AT,
        page_size: 10,
      },
    ]);
  });

  it("reads the caller's passes and one pass", async () => {
    const fake = fakeTransport({ my_passes: [PASS], get_pass: null });
    const passes = createAdmissionPasses({ transport: fake.transport });

    expect((await passes.mine().orThrow())[0]?.nonce).toBe("n0nce");
    expect(await passes.get("p9").orThrow()).toBeNull();
  });

  it("signs a token that expires with the pass", async () => {
    const { signer, jwks } = await keys();
    const fake = fakeTransport({ get_pass: PASS });

    const passes = createAdmissionPasses({
      transport: fake.transport,
      signer,
      jwks,
    });

    const pass = await passes.get("p1").orThrow();
    const token = await passes.token(pass!).orThrow();

    const [header, payload] = token
      .split(".")
      .slice(0, 2)
      .map((part) => JSON.parse(Buffer.from(part, "base64url").toString()));

    expect(header.typ).toBe(PASS_TOKEN_TYPE);
    expect(payload).toEqual({
      sub: "p1",
      jti: "n0nce",
      org: "org-1",
      kind: "ticket",
      name: "Jane",
      nbf: seconds(AT),
      exp: seconds(LATER),
    });
  });

  it("caps a token at the lifetime when the pass runs longer", async () => {
    const { signer } = await keys();

    const passes = createAdmissionPasses({
      transport: fakeTransport({ get_pass: BARE_PASS }).transport,
      signer,
      tokenLifetime: Temporal.Duration.from({ hours: 1 }),
    });

    const before = Date.now() / 1000;
    const pass = await passes.get("p2").orThrow();

    const token = await passes.token(pass!).orThrow();

    const payload = JSON.parse(
      Buffer.from(token.split(".")[1]!, "base64url").toString(),
    );

    expect(payload.name).toBeUndefined();
    expect(payload.exp).toBeGreaterThanOrEqual(Math.floor(before + 3600));
    expect(payload.exp).toBeLessThanOrEqual(
      Math.ceil(Date.now() / 1000 + 3600),
    );
  });

  it("fails to sign without a signer", async () => {
    const passes = createAdmissionPasses({
      transport: fakeTransport({}).transport,
    });

    const result = await passes.token({} as never);

    expect(result.ok ? undefined : result.error.hint).toBe(
      "PASS_SIGNER_MISSING",
    );
  });

  it("checks a verified token in with its id and nonce", async () => {
    const { sign, jwks } = await keys();

    const fake = fakeTransport({
      check_in_pass: { ...CHECK_IN, pass: { ...PASS, uses: 1 } },
    });

    const passes = createAdmissionPasses({
      transport: fake.transport,
      jwks: () => Promise.resolve(jwks),
    });

    const token = await sign(
      { sub: "p1", jti: "n0nce", exp: Date.now() / 1000 + 60 },
      { typ: PASS_TOKEN_TYPE },
    );

    const scan = await passes
      .checkIn(token, { method: "nfc", gate: "north", resourceId: "r1" })
      .orThrow();

    expect(fake.calls).toEqual([
      [
        "check_in_pass",
        {
          pass_id: "p1",
          nonce: "n0nce",
          method: "nfc",
          gate: "north",
          resource_id: "r1",
        },
      ],
    ]);
    expect(scan).toMatchObject({
      admitted: false,
      reason: "used_up",
      gate: "north",
      pass: { id: "p1", uses: 1 },
    });
  });

  it("turns a bad token away before the database", async () => {
    const { sign, jwks } = await keys();
    const fake = fakeTransport({});
    const passes = createAdmissionPasses({ transport: fake.transport, jwks });
    const now = Date.now() / 1000;
    const typ = { typ: PASS_TOKEN_TYPE };

    const hint = async (token: string) => {
      const result = await passes.checkIn(token);

      return result.ok ? undefined : result.error.hint;
    };

    const valid = await sign({ sub: "p1", jti: "n" }, typ);
    const [head, body] = valid.split(".");
    const forged = `${head}.${body}.${"A".repeat(86)}`;

    expect(await hint(forged)).toBe("PASS_TOKEN_INVALID");
    expect(await hint(await sign({ sub: "p1", jti: "n" }))).toBe(
      "PASS_TOKEN_INVALID",
    );
    expect(await hint(await sign({ sub: "p1" }, typ))).toBe(
      "PASS_TOKEN_INVALID",
    );
    expect(
      await hint(await sign({ sub: "p1", jti: "n", exp: now - 1 }, typ)),
    ).toBe("PASS_TOKEN_EXPIRED");
    expect(
      await hint(await sign({ sub: "p1", jti: "n", nbf: now + 600 }, typ)),
    ).toBe("PASS_TOKEN_EXPIRED");
    expect(fake.calls).toEqual([]);
  });

  it("fails to check in without a JWKS", async () => {
    const passes = createAdmissionPasses({
      transport: fakeTransport({}).transport,
    });

    const result = await passes.checkIn("a.b.c");

    expect(result.ok ? undefined : result.error.hint).toBe("PASS_JWKS_MISSING");
  });

  it("checks a holder in by hand", async () => {
    const fake = fakeTransport({
      check_in_pass: {
        ...CHECK_IN,
        method: "manual",
        admitted: true,
        reason: null,
        gate: null,
        pass: PASS,
      },
    });

    const passes = createAdmissionPasses({ transport: fake.transport });

    const scan = await passes.checkInManually("p1").orThrow();

    expect(fake.calls[0]).toEqual([
      "check_in_pass",
      {
        pass_id: "p1",
        nonce: null,
        method: "manual",
        gate: null,
        resource_id: null,
      },
    ]);
    expect(scan.admitted).toBe(true);
    expect("reason" in scan).toBe(false);
  });

  it("reads scans and occupancy", async () => {
    const fake = fakeTransport({
      list_pass_check_ins: [CHECK_IN],
      pass_occupancy: {
        resourceId: "r1",
        capacity: 4,
        booked: 2,
        dropIns: 1,
        free: 1,
      },
    });

    const passes = createAdmissionPasses({ transport: fake.transport });

    expect(
      (await passes.checkIns("p1", { pageSize: 5 }).orThrow())[0]?.reason,
    ).toBe("used_up");
    expect(await passes.occupancy("r1").orThrow()).toEqual({
      resourceId: "r1",
      capacity: 4,
      booked: 2,
      dropIns: 1,
      free: 1,
    });
    expect(fake.calls[0]).toEqual([
      "list_pass_check_ins",
      { pass_id: "p1", before: undefined, page_size: 5 },
    ]);
  });

  it("rejects a count that isn't an integer", async () => {
    const passes = createAdmissionPasses({
      transport: fakeTransport({
        pass_occupancy: {
          resourceId: "r1",
          capacity: "4",
          booked: 0,
          dropIns: 0,
          free: 4,
        },
      }).transport,
    });

    expect((await passes.occupancy("r1")).ok).toBe(false);
  });
});

describe("passes block", () => {
  it("lists and issues a record's passes through the section", async () => {
    const fake = fakeTransport({ list_passes: [PASS], issue_pass: PASS });

    const passes = createAdmissionPasses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const subject = { type: "event", id: "e1" };

    await admissionPassesBinding.load(passes, subject, undefined);
    await admissionPassesBinding.writes.issue.run(passes, subject, {
      resourceId: "r1",
    });

    expect(fake.calls.map(([fn, args]) => [fn, args["subject_id"]])).toEqual([
      ["list_passes", "e1"],
      ["issue_pass", "e1"],
    ]);
    expect(admissionPassesBlock.name).toBe("admission-passes");
  });

  it("validates the inputs", () => {
    expect(
      validate(passInputSchema, { kind: "visitor" }).issues,
    ).toBeUndefined();
    expect(validate(passInputSchema, { usesAllowed: 0 }).issues).toBeDefined();
    expect(
      validate(passSectionInputSchema, { holderEmail: "a" }).issues,
    ).toBeDefined();
  });
});
