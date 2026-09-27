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

  test("an unauthenticated visitor is redirected away from /capstones", async ({ page }) => {
    await page.goto("/capstones");
    await expect(page).toHaveURL(/\/login\?next=%2Fcapstones/);
  });

  test("an unauthenticated visitor is redirected away from /exams", async ({ page }) => {
    await page.goto("/exams");
    await expect(page).toHaveURL(/\/login\?next=%2Fexams/);
  });

  test("an unauthenticated visitor is redirected away from /mentor", async ({ page }) => {
    await page.goto("/mentor");
    await expect(page).toHaveURL(/\/login\?next=%2Fmentor/);
  });

  test("an unauthenticated visitor is redirected away from /scanner", async ({ page }) => {
    await page.goto("/scanner");
    await expect(page).toHaveURL(/\/login\?next=%2Fscanner/);
  });

  test("an unauthenticated visitor is redirected away from /investigate", async ({ page }) => {
    await page.goto("/investigate");
    await expect(page).toHaveURL(/\/login\?next=%2Finvestigate/);
  });

  test("an unauthenticated visitor is redirected away from /orgs", async ({ page }) => {
    await page.goto("/orgs");
    await expect(page).toHaveURL(/\/login\?next=%2Forgs/);
  });

  test("an unauthenticated visitor is redirected away from /reports", async ({ page }) => {
    await page.goto("/reports");
    await expect(page).toHaveURL(/\/login\?next=%2Freports/);
  });

  test("an unauthenticated visitor visiting an invite link is sent to login with next preserved", async ({
    page,
  }) => {
    await page.goto("/invite/some-token-value");
    await expect(page).toHaveURL(/\/login\?next=%2Finvite%2Fsome-token-value/);
  });

  test("an unauthenticated visitor is redirected away from an admin-only route", async ({ page }) => {
    await page.goto("/admin");
    await expect(page).toHaveURL(/\/login/);
  });

  test("an unauthenticated visitor visiting the MFA step-up page is sent to login", async ({ page }) => {
    await page.goto("/login/verify-mfa");
    await expect(page).toHaveURL(/\/login/);
  });

  test("an unauthenticated visitor is redirected away from the path import page", async ({ page }) => {
    await page.goto("/admin/paths/import");
    await expect(page).toHaveURL(/\/login/);
  });

  test("an unauthenticated visitor is redirected away from admin announcements", async ({ page }) => {
    await page.goto("/admin/announcements");
    await expect(page).toHaveURL(/\/login/);
  });

  test("an unauthenticated visitor is redirected away from admin ctf events", async ({ page }) => {
    await page.goto("/admin/ctf-events");
    await expect(page).toHaveURL(/\/login/);
  });
});

test.describe("i18n", () => {
  test("switching to Spanish on the landing page actually re-renders the heading and persists across reload", async ({
    page,
  }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toContainText(/skill, not course completion/i);

    await page.getByRole("button", { name: "Español" }).click();
    await expect(page.getByRole("heading", { level: 1 })).toContainText(/habilidad real/i);
    await expect(page.getByRole("navigation").getByRole("link", { name: "Iniciar sesión" })).toBeVisible();

    await page.reload();
    await expect(page.getByRole("heading", { level: 1 })).toContainText(/habilidad real/i);

    await page.getByRole("button", { name: "English" }).click();
    await expect(page.getByRole("heading", { level: 1 })).toContainText(/skill, not course completion/i);
  });
});

test.describe("PWA", () => {
  test("the landing page links a web app manifest with real icon URLs", async ({ page }) => {
    await page.goto("/");
    const manifestLink = page.locator('link[rel="manifest"]');
    await expect(manifestLink).toHaveAttribute("href", /\/manifest\.webmanifest$/);
    const manifestHref = await manifestLink.getAttribute("href");
    if (!manifestHref) throw new Error("manifest link has no href");
    const manifest = await page.evaluate(async (href) => {
      const response = await fetch(href);
      return response.json();
    }, manifestHref);
    expect(manifest.name).toBe("iCorePen");
    expect(manifest.icons).toHaveLength(2);
    for (const icon of manifest.icons) {
      const response = await page.request.get(icon.src);
      expect(response.status()).toBe(200);
      expect(response.headers()["content-type"]).toContain("image/png");
    }
  });

  test("/offline renders a real fallback page without requiring auth", async ({ page }) => {
    await page.goto("/offline");
    await expect(page.getByRole("heading", { level: 1 })).toContainText(/you're offline/i);
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

test.describe("mobile API auth", () => {
  test("an unauthenticated call to /api/mentor/chat gets a 401 JSON body, not a login redirect", async ({
    request,
  }) => {
    const response = await request.post("/api/mentor/chat", {
      data: { mode: "explain", message: "hello", contextType: "general" },
    });
    expect(response.status()).toBe(401);
    expect(response.headers()["content-type"]).toContain("application/json");
    const body = await response.json();
    expect(body).toEqual({ error: "Unauthorized" });
  });

  test("a bogus Bearer token on /api/mentor/chat is rejected with 401 JSON", async ({ request }) => {
    const response = await request.post("/api/mentor/chat", {
      headers: { Authorization: "Bearer not-a-real-token" },
      data: { mode: "explain", message: "hello", contextType: "general" },
    });
    expect(response.status()).toBe(401);
    const body = await response.json();
    expect(body).toEqual({ error: "Unauthorized" });
  });
});
