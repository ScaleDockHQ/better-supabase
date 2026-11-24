/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import { expect, test } from "@playwright/test";
import { expectInstant } from "better-supabase/testing";

import { signIn } from "./support/example-session";

// The agent story of supabase/seeds/areas-12-13.sql: the Renewals desk agent
// with a completed and a failed run, one tool call waiting for a decision and
// two guardrail hits. Load it with the reset (it is in [db.seed].sql_paths).

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the assistant panel names the page and record it was opened from", async ({
  page,
}) => {
  await page.goto("/crm/deals");
  await page
    .getByRole("link", { name: /^DEAL-\d+$/ })
    .first()
    .click();
  await page.waitForURL((url) => url.pathname.startsWith("/crm/deals/"));

  await page.getByRole("button", { name: "Assistant" }).click();

  const panel = page.getByRole("dialog");

  await expect(panel.getByText("Opened from")).toBeVisible();
  await expect(panel.getByText("deal", { exact: true })).toBeVisible();
});

test("an agent opens instantly, then its runs, approvals and guardrail hits stream in", async ({
  page,
}) => {
  await page.goto("/assistant/agents");

  const link = page.getByRole("link", { name: "Renewals desk" });

  await expect(link.first()).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.first().click();
      await page.waitForURL((url) =>
        /^\/assistant\/agents\/[\da-f-]{36}$/.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All agents" })],
  });

  const main = page.getByRole("main");

  await expect(main.getByTestId("kpi-band")).toBeVisible();

  await main.getByRole("link", { name: "Runs" }).click();
  await expect(
    main.getByText("The renewal tool timed out").or(main.getByText("failed")),
  ).toBeVisible();

  await main.getByRole("link", { name: "Approvals" }).click();
  await expect(main.getByText("requestDiscountApproval")).toBeVisible();
  await expect(
    main.getByRole("button", { name: "Approve" }).first(),
  ).toBeVisible();

  await main.getByRole("link", { name: "Guardrails" }).click();
  await expect(
    main.getByText("The reply left the renewal topic"),
  ).toBeVisible();
});

test("an approval is decided from the agent page without the model", async ({
  page,
}) => {
  await page.goto("/assistant/agents");
  await page.getByRole("link", { name: "Renewals desk" }).first().click();
  await page.waitForURL((url) =>
    /^\/assistant\/agents\/[\da-f-]{36}$/.test(url.pathname),
  );

  const main = page.getByRole("main");

  await main.getByRole("link", { name: "Approvals" }).click();

  const row = main.getByRole("row", { name: /waiveSetupFee/ });

  await row.getByRole("button", { name: "Approve" }).click();
  await expect(main.getByText("Approved").first()).toBeVisible();
  await expect(row).toHaveCount(0);
});

test("an eval run opens instantly with its scores and results", async ({
  page,
}) => {
  await page.goto("/assistant/evals/assistant.system");

  const open = page.getByRole("link", { name: "Open run" }).first();

  await expect(open).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await open.click();
      await page.waitForURL((url) =>
        /\/runs\/[\da-f-]{36}$/.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All evals" })],
  });

  const main = page.getByRole("main");

  await expect(main.getByTestId("kpi-band")).toBeVisible();
  await expect(
    main.getByText("When does the Globex contract renew?"),
  ).toBeVisible();
});

test("a workflow definition opens instantly with its progress and runs", async ({
  page,
}) => {
  const name = `Detail story ${Date.now()}`;

  await page.goto("/workflows");
  await page.getByLabel("Workflow name").fill(name);
  await page.getByRole("button", { name: "New workflow" }).click();
  await page.waitForURL((url) =>
    url.pathname.startsWith("/workflows/builder/"),
  );
  await page.goto("/workflows");

  const link = page.getByRole("link", { name }).first();

  await expect(link).toBeVisible();

  await expectInstant(page, {
    during: async () => {
      await link.click();
      await page.waitForURL((url) =>
        /^\/workflows\/[\da-f-]{36}$/.test(url.pathname),
      );
    },
    visible: [page.getByRole("link", { name: "All workflows" })],
  });

  const main = page.getByRole("main");

  await expect(main.getByRole("heading", { name })).toBeVisible();
  await expect(main.getByText("Progress")).toBeVisible();
  await expect(
    main.getByRole("link", { name: "Open in the builder" }),
  ).toBeVisible();
});

// oxlint-disable-next-line vitest/prefer-each -- Playwright has no `test.each` (1 finding).
for (const path of [
  "/assistant/agents",
  "/assistant/agents/runs",
  "/assistant/agents/approvals",
]) {
  test(`${path} streams its KPI band behind the header`, async ({ page }) => {
    await page.goto(path);
    await expect(page.getByRole("main").getByTestId("kpi-band")).toBeVisible();
  });
}
