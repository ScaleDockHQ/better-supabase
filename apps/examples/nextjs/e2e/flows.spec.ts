import { expect, type Page, test } from "@playwright/test";

import {
  clickSidebar,
  field,
  heading,
  openAccountMenu,
  pickInSubmenu,
  sidebarLink,
  signIn,
  visibleTestId,
  visibleText,
} from "./nav";
import { totp, totpStep } from "./totp";
import { password, users } from "./users";

/** The local stack's Mailpit (`[local_smtp]` in supabase/config.toml). */
const MAILPIT = "http://127.0.0.1:55424/api/v1";

async function latestLink(page: Page, to: string): Promise<string> {
  let body = "";
  await expect
    .poll(async () => {
      const search = await page.request.get(
        `${MAILPIT}/search?query=${encodeURIComponent(`to:"${to}"`)}`,
      );
      const { messages } = (await search.json()) as {
        messages: { ID: string }[];
      };
      const id = messages[0]?.ID;
      if (!id) return false;
      const message = await page.request.get(`${MAILPIT}/message/${id}`);
      body = ((await message.json()) as { Text: string }).Text;
      return true;
    })
    .toBe(true);
  const link = /https?:\/\/\S+\/auth\/v1\/verify\S+/.exec(body)?.[0];
  if (!link) throw new Error(`No verify link in the email to ${to}`);
  return link.replaceAll("&amp;", "&");
}

/** A property on `window` survives client navigations and dies on a full load. */
async function markDocument(page: Page): Promise<void> {
  await page.evaluate(() => Object.assign(window, { e2eMark: true }));
}

async function sameDocument(page: Page): Promise<boolean> {
  return page.evaluate(() => "e2eMark" in window);
}

test("sign in and sign out", async ({ page }) => {
  await page.goto("/en/customers");
  await expect(page).toHaveURL(
    (url) =>
      url.pathname === "/en/login" &&
      url.searchParams.get("next") === "/en/customers",
  );
  await field(page, "Email").fill(users.member.email);
  await field(page, "Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => url.pathname === "/en/customers");
  await expect(visibleTestId(page, "role")).toHaveText("Member");

  await openAccountMenu(page);
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await page.waitForURL((url) => url.pathname === "/en/login");
  await page.goto("/en");
  await expect(page).toHaveURL((url) => url.pathname === "/en/login");
});

test("a wrong password shows an error", async ({ page }) => {
  await page.goto("/en/login");
  await field(page, "Email").fill(users.member.email);
  await field(page, "Password").fill("not-the-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(
    page.getByText("That email and password don't match."),
  ).toBeVisible();
});

test("sign up starts without an organization", async ({ page }) => {
  const email = `signup-${String(Date.now())}@example.test`;
  await page.goto("/en/signup");
  await field(page, "Full name").fill("New Person");
  await field(page, "Email").fill(email);
  await field(page, "Password").fill(password);
  await page.getByRole("button", { name: "Create account" }).click();
  await page.waitForURL((url) => url.pathname === "/en");
  await expect(visibleTestId(page, "organization-name")).toHaveText(
    "No organization",
  );
});

test("two-factor sign-in asks for the code, and unlocks deleting the account", async ({
  page,
}) => {
  const email = `mfa-${String(Date.now())}@example.test`;
  await page.goto("/en/signup");
  await field(page, "Full name").fill("Two Factor");
  await field(page, "Email").fill(email);
  await field(page, "Password").fill(password);
  await page.getByRole("button", { name: "Create account" }).click();
  await page.waitForURL((url) => url.pathname === "/en");

  await page.goto("/en/settings/security");
  await expect(visibleTestId(page, "mfa-status")).toHaveText("Off");
  await page.getByRole("button", { name: "Set up" }).click();
  const hint = await visibleText(
    page,
    /^Or enter this key by hand: /,
  ).textContent();
  const secret = hint?.replace("Or enter this key by hand: ", "").trim() ?? "";
  expect(secret).toMatch(/^[A-Z2-7]+=*$/);
  const enrolledAt = totpStep();
  await field(page, "Code from the app").fill(totp(secret, enrolledAt));
  await page.getByRole("button", { name: "Verify" }).click();
  await expect(visibleTestId(page, "mfa-status")).toHaveText("On");

  await openAccountMenu(page);
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await page.waitForURL((url) => url.pathname === "/en/login");
  await signIn(page, email, "en", "/en/mfa");
  // A code is accepted once, and the Auth server allows one step of skew.
  await field(page, "Code").fill(
    totp(secret, Math.max(totpStep(), enrolledAt + 1)),
  );
  await page.getByRole("button", { name: "Verify" }).click();
  await page.waitForURL((url) => url.pathname === "/en");
  await expect(heading(page, "Dashboard")).toBeVisible();

  await page.goto("/en/settings/security");
  await page.getByRole("button", { name: "Delete account" }).click();
  await page.getByRole("button", { name: "Delete", exact: true }).click();
  await page.waitForURL((url) => url.pathname === "/en/login");
  await field(page, "Email").fill(email);
  await field(page, "Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(
    visibleText(page, "That email and password don't match."),
  ).toBeVisible();
});

test("reset a forgotten password through the email link", async ({ page }) => {
  const email = `reset-${String(Date.now())}@example.test`;
  await page.goto("/en/signup");
  await field(page, "Full name").fill("Reset Person");
  await field(page, "Email").fill(email);
  await field(page, "Password").fill(password);
  await page.getByRole("button", { name: "Create account" }).click();
  await page.waitForURL((url) => url.pathname === "/en");
  await openAccountMenu(page);
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await page.waitForURL((url) => url.pathname === "/en/login");

  await page.getByRole("link", { name: "Forgot your password?" }).click();
  await page.waitForURL((url) => url.pathname === "/en/forgot-password");
  await field(page, "Email").fill(email);
  await page.getByRole("button", { name: "Send reset link" }).click();
  await expect(
    page.getByText(
      "If that address has an account, a reset link is on its way.",
    ),
  ).toBeVisible();

  await page.goto(await latestLink(page, email));
  await page.waitForURL((url) => url.pathname === "/en/reset-password");
  await field(page, "New password").fill("a-new-password");
  await field(page, "Repeat it").fill("a-new-password");
  await page.getByRole("button", { name: "Change password" }).click();
  await page.waitForURL((url) => url.pathname === "/en");

  await openAccountMenu(page);
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await page.waitForURL((url) => url.pathname === "/en/login");
  await field(page, "Email").fill(email);
  await field(page, "Password").fill("a-new-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL((url) => url.pathname === "/en");
});

test("switching organizations changes the menu and the data without a reload", async ({
  page,
}) => {
  await signIn(page, users.admin.email);
  await expect(visibleTestId(page, "organization-name")).toHaveText("Acme");
  await expect(sidebarLink(page, "Beta")).toBeVisible();
  await markDocument(page);

  await page.getByRole("button", { name: "Switch organization" }).click();
  await page.getByRole("menuitem", { name: /Globex/ }).click();
  await expect(visibleTestId(page, "organization-name")).toHaveText("Globex");
  await expect(visibleTestId(page, "role")).toHaveText("Member");
  await expect(sidebarLink(page, "Beta")).toHaveCount(0);
  await clickSidebar(page, "Customers", "/en/customers")();
  await expect(page.getByRole("link", { name: "Initech" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Road Runner Inc" })).toHaveCount(
    0,
  );
  expect(await sameDocument(page)).toBe(true);

  // The active organization is stored per user; the other specs expect Acme.
  await page.getByRole("button", { name: "Switch organization" }).click();
  await page.getByRole("menuitem", { name: /Acme/ }).click();
  await expect(visibleTestId(page, "organization-name")).toHaveText("Acme");
  await clickSidebar(page, "Customers", "/en/customers")();
  await expect(
    page.getByRole("link", { name: "Road Runner Inc" }),
  ).toBeVisible();
  await expect(page.getByRole("link", { name: "Initech" })).toHaveCount(0);
});

test.describe("preferences", () => {
  test.use({ storageState: users.member.storageState });

  test("the language switch keeps the page and translates it", async ({
    page,
  }) => {
    await page.goto("/en/customers");
    await expect(heading(page, "Customers")).toBeVisible();
    await pickInSubmenu(page, "Language", "Nederlands");
    await page.waitForURL((url) => url.pathname === "/nl/customers");
    await expect(heading(page, "Klanten")).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", "nl");
    await expect(sidebarLink(page, "Instellingen")).toBeVisible();
  });

  test("the theme is applied before the first paint after a reload", async ({
    page,
  }) => {
    await page.goto("/en");
    await pickInSubmenu(page, "Theme", "Dark");
    await expect(page.locator("html")).toHaveClass(/\bdark\b/);

    // Read when the parser reaches <body>: the inline script in <head> has
    // run, and nothing has painted yet.
    await page.addInitScript(() => {
      document.addEventListener(
        "readystatechange",
        () => {
          if (document.readyState === "interactive")
            Object.assign(window, {
              e2eFirstClass: document.documentElement.className,
            });
        },
        { once: true },
      );
    });
    await page.reload();
    expect(
      await page.evaluate(() =>
        "e2eFirstClass" in window ? window.e2eFirstClass : null,
      ),
    ).toMatch(/\bdark\b/);

    await pickInSubmenu(page, "Theme", "Light");
    await expect(page.locator("html")).not.toHaveClass(/\bdark\b/);
  });
});

test("an invited person signs up and joins the organization", async ({
  browser,
  page,
}) => {
  const email = `invitee-${String(Date.now())}@example.test`;
  await signIn(page, users.admin.email);
  await page.goto("/en/settings/members");
  await page.getByRole("button", { name: "Invite", exact: true }).click();
  await field(page, "Email").fill(email);
  await page.getByRole("button", { name: "Send invitation" }).click();
  const link = await page.getByTestId("invite-link").inputValue();
  expect(link).toContain("/en/invite/");

  const invitee = await (await browser.newContext()).newPage();
  await invitee.goto(link);
  await expect(visibleText(invitee, "Join Acme")).toBeVisible();
  await invitee.getByRole("link", { name: "Create an account" }).click();
  await field(invitee, "Full name").fill("Invited Person");
  await field(invitee, "Email").fill(email);
  await field(invitee, "Password").fill(password);
  await invitee.getByRole("button", { name: "Create account" }).click();
  await invitee.waitForURL((url) => url.pathname.startsWith("/en/invite/"));
  await invitee.getByRole("button", { name: "Accept invitation" }).click();
  await invitee.waitForURL((url) => url.pathname === "/en");
  await expect(visibleTestId(invitee, "organization-name")).toHaveText("Acme");
  await expect(visibleTestId(invitee, "role")).toHaveText("Member");
  await expect(sidebarLink(invitee, "Customers")).toBeVisible();
  await invitee.context().close();

  await page.reload();
  await expect(visibleText(page, email)).toBeVisible();
  await page.goto("/en/settings/audit");
  await expect(
    page
      .getByRole("row")
      .filter({ hasText: "invitation.accepted" })
      .filter({ hasText: "Acme" }),
  ).toBeVisible();
});
