import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  contractChangesSchema,
  contractInputSchema,
  contractsBlock,
  contractsSection,
  createContracts,
  obligationInputSchema,
} from "../../../src/blocks/contracts/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";
const PARTY = { type: "party", id: "p1" };

const FULL = {
  id: "k1",
  organizationId: "org-1",
  title: "Master services agreement",
  description: "Hosting and support",
  counterpartyType: "party",
  counterpartyId: "p1",
  ownerId: "u1",
  status: "active",
  value: "1200000",
  currency: "EUR",
  startsOn: "2026-01-01",
  endsOn: "2026-12-31",
  autoRenew: true,
  renewalMonths: 12,
  noticeDays: 30,
  noticeDeadline: "2026-12-01",
  renewedCount: 1,
  signatureRequestId: "s1",
  signedAt: AT,
  terminatedAt: AT,
  terminationReason: "Breach",
  createdBy: "u0",
  createdAt: AT,
  updatedAt: AT,
  fields: { region: "emea" },
};

const MINIMAL = {
  id: "k2",
  organizationId: "org-1",
  title: "NDA",
  status: "draft",
  renewalMonths: "12",
  noticeDays: null,
  createdAt: AT,
  updatedAt: AT,
};

const OBLIGATION = {
  id: "o1",
  organizationId: "org-1",
  contractId: "k1",
  title: "Quarterly report",
  description: "Usage report",
  dueOn: "2026-11-01",
  ownerId: "u1",
  status: "done",
  overdue: false,
  completedAt: AT,
  completedBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_OBLIGATION = {
  id: "o2",
  organizationId: "org-1",
  contractId: "k1",
  title: "Kick-off",
  status: "open",
  overdue: true,
  dueOn: "",
  createdAt: AT,
  updatedAt: AT,
};

const Fields = v.object({ region: v.picklist(["emea", "amer"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createContracts", () => {
  it("creates a draft with every attribute and reads every column back", async () => {
    const t = fieldsTransport({ create_contract: () => FULL });
    const contracts = createContracts({ transport: t });

    const contract = await contracts
      .create("org-1", {
        title: "Master services agreement",
        description: "Hosting and support",
        counterparty: PARTY,
        ownerId: "u1",
        value: money(1_200_000n, "EUR"),
        startsOn: Temporal.PlainDate.from("2026-01-01"),
        endsOn: Temporal.PlainDate.from("2026-12-31"),
        autoRenew: true,
        renewalMonths: 12,
        noticeDays: 30,
      })
      .orThrow();

    expect(t.calls).toEqual([
      [
        "create_contract",
        {
          tenant: "org-1",
          attrs: {
            title: "Master services agreement",
            description: "Hosting and support",
            counterpartyType: "party",
            counterpartyId: "p1",
            ownerId: "u1",
            value: "1200000",
            currency: "EUR",
            startsOn: "2026-01-01",
            endsOn: "2026-12-31",
            autoRenew: true,
            renewalMonths: 12,
            noticeDays: 30,
          },
        },
      ],
    ]);
    expect(contract).toMatchObject({
      id: "k1",
      counterparty: PARTY,
      value: money(1_200_000n, "EUR"),
      status: "active",
      autoRenew: true,
      renewedCount: 1,
      signatureRequestId: "s1",
      terminationReason: "Breach",
      createdBy: "u0",
      fields: { region: "emea" },
    });
    expect(contract.noticeDeadline?.toString()).toBe("2026-12-01");
    expect(contract.signedAt?.toString()).toBe(AT);
  });

  it("leaves out the columns a draft doesn't have", async () => {
    const t = fieldsTransport({ get_contract: () => MINIMAL });

    const contract = await createContracts({ transport: t })
      .get("k2")
      .orThrow();

    expect(Object.keys(contract).toSorted()).toEqual([
      "autoRenew",
      "createdAt",
      "fields",
      "id",
      "noticeDays",
      "organizationId",
      "renewalMonths",
      "renewedCount",
      "status",
      "title",
      "updatedAt",
    ]);
    expect(contract).toMatchObject({
      autoRenew: false,
      renewalMonths: 12,
      noticeDays: 0,
      renewedCount: 0,
    });
    expect(t.calls).toEqual([["get_contract", { contract_id: "k2" }]]);
  });

  it("writes and checks the extra fields on create and update", async () => {
    const t = fieldsTransport({
      create_contract: () => FULL,
      update_contract: () => FULL,
    });

    const contracts = createContracts({ transport: t, fields: Fields });

    const created = await contracts
      .create("org-1", { title: "MSA", fields: { region: "emea" } })
      .orThrow();

    expect(created.fields.region).toBe("emea");
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      attrs: { title: "MSA" },
      fields: { region: "emea" },
    });

    const refused = await contracts.update("k1", {
      // SAFETY: a value the schema refuses, to prove the client checks it.
      fields: { region: "mars" } as unknown as { region: "emea" },
    });

    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");

    await contracts.update("k1", { noticeDays: 60 }).orThrow();
    await contracts.update("k1", { fields: { region: "amer" } }).orThrow();

    expect(t.calls[1]).toEqual([
      "update_contract",
      { contract_id: "k1", attrs: { noticeDays: 60 } },
    ]);
    expect(t.calls[2]?.[1]["fields"]).toEqual({ region: "amer" });
  });

  it("returns a validation error for a stored value the schema refuses", async () => {
    const t = fieldsTransport({
      get_contract: () => ({ ...FULL, fields: { region: "x" } }),
    });

    const read = await createContracts({ transport: t, fields: Fields }).get(
      "k1",
    );

    expect(read.ok ? undefined : read.error.kind).toBe("validation");
  });

  it("moves a contract through its lifecycle and out for signature", async () => {
    const t = fieldsTransport({
      transition_contract: () => FULL,
      send_contract_for_signature: () => FULL,
    });

    const contracts = createContracts({ transport: t });

    await contracts.transition("k1", "submit").orThrow();
    await contracts.transition("k1", "terminate", "Breach").orThrow();
    await contracts.sendForSignature("k1", { signers: ["u1"] }).orThrow();
    await contracts
      .sendForSignature("k1", {
        signers: ["u1", "u2"],
        signOrder: "sequential",
        message: "Please sign",
      })
      .orThrow();

    expect(t.calls).toEqual([
      [
        "transition_contract",
        { contract_id: "k1", action: "submit", reason: null },
      ],
      [
        "transition_contract",
        { contract_id: "k1", action: "terminate", reason: "Breach" },
      ],
      [
        "send_contract_for_signature",
        {
          contract_id: "k1",
          signers: ["u1"],
          sign_order: "parallel",
          message: null,
        },
      ],
      [
        "send_contract_for_signature",
        {
          contract_id: "k1",
          signers: ["u1", "u2"],
          sign_order: "sequential",
          message: "Please sign",
        },
      ],
    ]);
  });

  it("lists an organization's contracts and a counterparty's", async () => {
    const t = fieldsTransport({ list_contracts: () => [FULL, MINIMAL] });
    const contracts = createContracts({ transport: t });

    const listed = await contracts.list("org-1").orThrow();

    await contracts
      .list("org-1", {
        status: "active",
        ownerId: "u1",
        renewingBefore: Temporal.PlainDate.from("2027-01-01"),
        before: Temporal.Instant.from(AT),
        pageSize: 10,
      })
      .orThrow();
    await contracts.forCounterparty(PARTY).orThrow();

    expect(listed.map((contract) => contract.id)).toEqual(["k1", "k2"]);
    expect(t.calls).toEqual([
      [
        "list_contracts",
        {
          tenant: "org-1",
          status: null,
          counterparty_type: null,
          counterparty_id: null,
          owner_id: null,
          renewing_before: null,
          before: null,
          page_size: null,
        },
      ],
      [
        "list_contracts",
        {
          tenant: "org-1",
          status: "active",
          counterparty_type: null,
          counterparty_id: null,
          owner_id: "u1",
          renewing_before: "2027-01-01",
          before: AT,
          page_size: 10,
        },
      ],
      [
        "list_contracts",
        {
          tenant: null,
          status: null,
          counterparty_type: "party",
          counterparty_id: "p1",
          owner_id: null,
          renewing_before: null,
          before: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("runs the renewals", async () => {
    const t = fieldsTransport({
      run_contract_renewals: () => ({ renewed: 2, expired: "1" }),
    });

    const contracts = createContracts({ transport: t });

    expect(await contracts.runRenewals().orThrow()).toEqual({
      renewed: 2,
      expired: 1,
    });
    await contracts
      .runRenewals(Temporal.PlainDate.from("2026-12-31"))
      .orThrow();

    expect(t.calls).toEqual([
      ["run_contract_renewals", { as_of: null }],
      ["run_contract_renewals", { as_of: "2026-12-31" }],
    ]);
  });

  it("saves, settles, deletes and lists obligations", async () => {
    const t = fieldsTransport({
      save_obligation: () => OBLIGATION,
      set_obligation_status: () => OBLIGATION,
      delete_obligation: () => BARE_OBLIGATION,
      list_obligations: () => [OBLIGATION, BARE_OBLIGATION],
    });

    const contracts = createContracts({ transport: t });

    const saved = await contracts
      .saveObligation("k1", {
        title: "Quarterly report",
        description: "Usage report",
        dueOn: Temporal.PlainDate.from("2026-11-01"),
        ownerId: "u1",
        obligationId: "o1",
      })
      .orThrow();

    await contracts.saveObligation("k1", { title: "Kick-off" }).orThrow();
    await contracts.setObligationStatus("o1", "done").orThrow();

    const deleted = await contracts.deleteObligation("o2").orThrow();
    const listed = await contracts.obligations("org-1").orThrow();

    await contracts
      .obligations("org-1", {
        contractId: "k1",
        ownerId: "u1",
        openOnly: true,
        dueBefore: Temporal.PlainDate.from("2026-12-01"),
        pageSize: 5,
      })
      .orThrow();

    expect(saved).toMatchObject({
      status: "done",
      ownerId: "u1",
      completedBy: "u1",
      description: "Usage report",
    });
    expect(saved.dueOn?.toString()).toBe("2026-11-01");
    expect(saved.completedAt?.toString()).toBe(AT);
    expect(Object.keys(deleted).toSorted()).toEqual([
      "contractId",
      "createdAt",
      "id",
      "organizationId",
      "overdue",
      "status",
      "title",
      "updatedAt",
    ]);
    expect(deleted.overdue).toBe(true);
    expect(listed).toHaveLength(2);
    expect(t.calls).toEqual([
      [
        "save_obligation",
        {
          contract_id: "k1",
          title: "Quarterly report",
          due_on: "2026-11-01",
          owner_id: "u1",
          description: "Usage report",
          obligation_id: "o1",
        },
      ],
      [
        "save_obligation",
        {
          contract_id: "k1",
          title: "Kick-off",
          due_on: null,
          owner_id: null,
          description: null,
          obligation_id: null,
        },
      ],
      ["set_obligation_status", { obligation_id: "o1", status: "done" }],
      ["delete_obligation", { obligation_id: "o2" }],
      [
        "list_obligations",
        {
          tenant: "org-1",
          contract_id: null,
          owner_id: null,
          open_only: false,
          due_before: null,
          page_size: null,
        },
      ],
      [
        "list_obligations",
        {
          tenant: "org-1",
          contract_id: "k1",
          owner_id: "u1",
          open_only: true,
          due_before: "2026-12-01",
          page_size: 5,
        },
      ],
    ]);
  });

  it("rejects malformed rows", async () => {
    const t = fieldsTransport({
      get_contract: () => ({ ...MINIMAL, status: "lost" }),
      delete_obligation: () => ({ ...BARE_OBLIGATION, status: "late" }),
      run_contract_renewals: () => [],
    });

    const contracts = createContracts({ transport: t });

    expect((await contracts.get("k2")).ok).toBe(false);
    expect((await contracts.deleteObligation("o2")).ok).toBe(false);
    expect((await contracts.runRenewals()).ok).toBe(false);
  });

  it("runs the hooks and logs through the logger", async () => {
    const seen: string[] = [];

    const contracts = createContracts({
      transport: fieldsTransport({ get_contract: () => MINIMAL }),
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: {
        get: {
          after: () => {
            seen.push("get");
          },
        },
      },
    });

    await contracts.get("k2").orThrow();

    expect(seen).toEqual(["get"]);
  });
});

describe("contracts block", () => {
  it("loads a counterparty's contracts on its record page", async () => {
    const t = fieldsTransport({ list_contracts: () => [MINIMAL] });
    const contracts = createContracts({ transport: t });

    const loaded = await contractsSection.load(contracts, PARTY, undefined);

    expect(loaded.ok ? loaded.data.map((row) => row.id) : []).toEqual(["k2"]);
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: null,
      counterparty_type: "party",
      counterparty_id: "p1",
    });
    expect(contractsBlock.name).toBe("contracts");
  });

  it("validates the inputs", () => {
    expect(
      validate(contractInputSchema, {
        title: "MSA",
        value: { amount: 100n, currency: "EUR" },
        noticeDays: 30,
      }).issues,
    ).toBeUndefined();
    expect(validate(contractInputSchema, { title: "" }).issues).toBeDefined();
    expect(
      validate(contractChangesSchema, { renewalMonths: 0 }).issues,
    ).toBeDefined();
    expect(validate(contractChangesSchema, {}).issues).toBeUndefined();
    expect(
      validate(obligationInputSchema, { title: "Report", dueOn: "soon" })
        .issues,
    ).toBeDefined();
  });
});
