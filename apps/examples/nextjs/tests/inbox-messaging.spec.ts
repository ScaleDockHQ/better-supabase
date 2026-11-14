/* oxlint-disable vitest/prefer-importing-vitest-globals -- `test` and `expect`
   come from @playwright/test, which the rule reads as Vitest globals (1 finding). */
import type { Locator } from "@playwright/test";

import { expect, test } from "@playwright/test";

import { signIn } from "./support/example-session";

// Findings EX-403, EX-422 and EX-030: the inbox admin tools, the team queue,
// notes with mentions and the message scroller on the Help sheet and /chat.

/**
 * Lazy triggers load their code on first intent and ignore a click that lands
 * before hydration, so click again until the panel is there.
 */
async function openWith(trigger: Locator, panel: Locator): Promise<void> {
  await trigger.hover();
  await expect(async () => {
    await trigger.click();
    await expect(panel).toBeVisible({ timeout: 3000 });
  }).toPass({ timeout: 30_000 });
}

test("the webhook events sheet lists the failed event and queues a replay", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/inbox");

  await openWith(
    page.getByRole("button", { name: "Webhook events" }),
    page.getByRole("dialog"),
  );

  await expect(page.getByText(/whatsapp/u).first()).toBeVisible();

  await page.getByRole("button", { name: "Replay" }).click();

  await expect(page.getByText("Queued for replay")).toBeVisible();
});

test("a broadcast reaches the open conversations of a channel", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/inbox");

  await openWith(
    page.getByRole("button", { name: "Broadcast" }),
    page.getByRole("dialog"),
  );
  await page.getByLabel("Message").fill("We are fixing an outage.");
  await page.getByRole("button", { name: "Send broadcast" }).click();

  await expect(page.getByText(/Sent to \d+ conversations/u)).toBeVisible();
});

test("a conversation goes to a team queue and its note mentions a teammate", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/inbox");

  await page
    .getByRole("link", { name: /Invoice 1042 is overdue/u })
    .first()
    .click();

  const thread = page.getByRole("region", { name: "Invoice 1042 is overdue" });

  await openWith(
    thread.getByRole("button", { name: /^(Team queue|Support|Sales)$/u }),
    page.getByRole("menuitem", { name: "Support" }),
  );
  await page.getByRole("menuitem", { name: "Support" }).click();

  await expect(thread.getByRole("button", { name: "Support" })).toBeVisible();

  await page.getByRole("switch", { name: "Internal note" }).click();
  await page.getByRole("button", { name: "Mention" }).click();
  await page.getByRole("menuitem").first().click();
  await page.getByRole("button", { name: "Add note" }).click();

  await expect(page.getByText("Internal note ·").last()).toBeVisible();
});

test("the contact name opens the CRM person", async ({ page }) => {
  await signIn(page);
  await page.goto("/inbox");

  await page
    .getByRole("link", { name: /Invoice 1042 is overdue/u })
    .first()
    .click();

  await expect(
    page
      .getByRole("complementary", { name: "Contact" })
      .getByRole("link", { name: "Wile E. Coyote" }),
  ).toHaveAttribute("href", /\/crm\/contacts\//u);
});

test("the Help sheet shows the thread on the message scroller", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/");

  const sheet = page.getByRole("dialog");

  await openWith(page.getByRole("button", { name: "Help" }), sheet);

  await sheet
    .getByRole("textbox", { name: "Message" })
    .fill("Where do I find my invoices?");
  await sheet.getByRole("button", { name: "Send" }).click();

  await expect(
    page
      .locator('[data-slot="message-scroller"]')
      .getByText("Where do I find my invoices?"),
  ).toBeVisible();
});

test("/chat renders channel messages on the message scroller", async ({
  page,
}) => {
  await signIn(page);
  await page.goto("/chat");

  await page.getByRole("button", { name: "Create a channel" }).click();

  const channel = `ship-${Date.now()}`;

  await page.getByLabel("Name").fill(channel);
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page
    .getByTestId("channels")
    .getByRole("button", { name: channel })
    .click();

  await page.getByPlaceholder(/^Message #/u).fill("Shipping today");
  await page.getByRole("button", { name: "Send" }).click();

  await expect(
    page.locator('[data-slot="message-scroller"]').getByText("Shipping today"),
  ).toBeVisible();

  await page.getByRole("button", { name: "Reply in thread" }).click();
  await page.getByPlaceholder("Reply in the thread").fill("On it");
  await page.getByRole("button", { name: "Send" }).last().click();

  await expect(
    page.locator('[data-slot="message-scroller"]').getByText("On it"),
  ).toBeVisible();
});
