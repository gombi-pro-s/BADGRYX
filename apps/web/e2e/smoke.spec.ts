import { expect, test } from "@playwright/test";

test.describe("public pages", () => {
  test("landing page renders with sign up / log in entry points", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toContainText(
      /skill, not course completion/i,
    );
    const nav = page.getByRole("navigation");
    await expect(nav.getByRole("link", { name: "Log in" })).toBeVisible();
    await expect(nav.getByRole("link", { name: "Sign up" })).toBeVisible();
  });

  test("login page renders a real email/password form", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByLabel("Email")).toBeVisible();
    await expect(page.getByLabel("Password", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Log in" })).toBeVisible();
  });

  test("signup page renders a real email/password form", async ({ page }) => {
    await page.goto("/signup");
    await expect(page.getByLabel("Email")).toBeVisible();
    await expect(page.getByLabel("Password", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Create account" })).toBeVisible();
  });

  test("forgot-password page renders and can be reached from login", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("link", { name: "Forgot password?" }).click();
    await expect(page).toHaveURL(/\/forgot-password$/);
    await expect(page.getByLabel("Email")).toBeVisible();
  });
});

test.describe("auth wall", () => {
  test("an unauthenticated visitor is redirected away from /dashboard", async ({ page }) => {
    await page.goto("/dashboard");
    await expect(page).toHaveURL(/\/login\?next=%2Fdashboard/);
  });

  test("an unauthenticated visitor is redirected away from /skills", async ({ page }) => {
    await page.goto("/skills");
    await expect(page).toHaveURL(/\/login\?next=%2Fskills/);
  });

  test("an unauthenticated visitor is redirected away from /settings", async ({ page }) => {
    await page.goto("/settings");
    await expect(page).toHaveURL(/\/login\?next=%2Fsettings/);
  });

  test("an unauthenticated visitor is redirected away from /learn", async ({ page }) => {
    await page.goto("/learn");
    await expect(page).toHaveURL(/\/login\?next=%2Flearn/);
  });

  test("an unauthenticated visitor is redirected away from /labs", async ({ page }) => {
    await page.goto("/labs");
    await expect(page).toHaveURL(/\/login\?next=%2Flabs/);
  });

  test("an unauthenticated visitor is redirected away from /ctf", async ({ page }) => {
    await page.goto("/ctf");
    await expect(page).toHaveURL(/\/login\?next=%2Fctf/);
  });

  test("an unauthenticated visitor is redirected away from /mentor", async ({ page }) => {
    await page.goto("/mentor");
    await expect(page).toHaveURL(/\/login\?next=%2Fmentor/);
  });

  test("an unauthenticated visitor is redirected away from an admin-only route", async ({ page }) => {
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/login/);
  });
});

test.describe("login form validation", () => {
  test("shows an error for invalid credentials rather than a stack trace", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel("Email").fill("nobody@example.com");
    await page.getByLabel("Password", { exact: true }).fill("wrong-password-123");
    await page.getByRole("button", { name: "Log in" }).click();
    await expect(page.getByRole("alert")).toBeVisible({ timeout: 15_000 });
  });
});
