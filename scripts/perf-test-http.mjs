#!/usr/bin/env node
// ============================================================================
// Load test against a real, running production build of this app's public
// pages ("/", "/login", "/signup") -- no live Supabase project needed for
// these three, since none of them touch the database. Hand-rolled (no new
// dependency: just Node's built-in fetch + child_process), matching this
// project's zero-new-dependency approach elsewhere (Turnstile's hand-rolled
// fetch/crypto).
//
// What this gates on: zero request failures under concurrent load (a
// correctness signal: did the server actually survive, not "was it fast
// enough"). Latency percentiles are printed for a human to read, not
// gated -- this sandbox's hardware is shared/variable, so a hard-coded
// millisecond budget would fail for reasons that have nothing to do with a
// real regression in the app.
//
// Usage: node scripts/perf-test-http.mjs
// Env: PERF_PORT (default 3200), PERF_DURATION_SECONDS (default 15),
//      PERF_CONCURRENCY (default 20)
// Assumes `next build` has already been run in apps/web (same assumption
// e2e's playwright.config.ts webServer makes).
// ============================================================================
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WEB_DIR = path.join(ROOT_DIR, "apps", "web");

const PORT = process.env.PERF_PORT ?? "3200";
const DURATION_SECONDS = Number(process.env.PERF_DURATION_SECONDS ?? "15");
const CONCURRENCY = Number(process.env.PERF_CONCURRENCY ?? "20");
const BASE_URL = `http://127.0.0.1:${PORT}`;
const ROUTES = ["/", "/login", "/signup"];

function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  const idx = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[idx];
}

async function waitForServer(url, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url);
      if (res.ok || res.status < 500) return true;
    } catch {
      // not up yet
    }
    await new Promise((r) => setTimeout(r, 300));
  }
  return false;
}

async function runWorker(results, stopAt) {
  let i = 0;
  while (Date.now() < stopAt) {
    const route = ROUTES[i % ROUTES.length];
    i += 1;
    const start = performance.now();
    try {
      const res = await fetch(BASE_URL + route, { redirect: "manual" });
      // A 3xx (e.g. the auth wall's redirect) is a correct, expected
      // response for these routes, not a failure -- only 5xx/network
      // errors count against the server surviving load.
      const ok = res.status < 500;
      results.push({ route, ms: performance.now() - start, ok, status: res.status });
    } catch (err) {
      results.push({ route, ms: performance.now() - start, ok: false, error: String(err) });
    }
  }
}

// Kills the whole process group the server was spawned into, not just its
// own pid. Spawning via npx (or any wrapper) means the wrapper can fork the
// real `next-server` as a *child* rather than exec-replacing itself with
// it -- killing only the wrapper's pid then orphans that child (reparented
// to pid 1), which keeps running and holding the port forever. Spawning
// the local next binary directly with detached:true and killing the
// negative pid (the process group) avoids that regardless of how next
// itself forks internally, with a SIGKILL fallback if SIGTERM doesn't land.
async function killServerGroup(server) {
  if (server.exitCode !== null || server.killed) return;
  try {
    process.kill(-server.pid, "SIGTERM");
  } catch {
    // group already gone
  }
  await new Promise((resolve) => {
    const timer = setTimeout(() => {
      try {
        process.kill(-server.pid, "SIGKILL");
      } catch {
        // already gone
      }
      resolve();
    }, 3000);
    server.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

async function main() {
  console.log(`==> Starting production server on ${BASE_URL} (apps/web)`);
  const nextBin = path.join(WEB_DIR, "node_modules", ".bin", "next");
  const server = spawn(nextBin, ["start", "-p", PORT], {
    cwd: WEB_DIR,
    env: {
      ...process.env,
      NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://placeholder.supabase.co",
      NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "placeholder-anon-key",
    },
    stdio: ["ignore", "pipe", "pipe"],
    detached: true,
  });
  // Last-resort synchronous safety net: if anything below throws in a way
  // the explicit awaited killServerGroup() calls never run, this still
  // fires on the way out (process.exit's "exit" event is synchronous-only,
  // hence SIGKILL directly rather than the graceful SIGTERM-then-wait).
  process.on("exit", () => {
    try {
      process.kill(-server.pid, "SIGKILL");
    } catch {
      // already gone
    }
  });
  let serverOutput = "";
  server.stdout.on("data", (d) => (serverOutput += d));
  server.stderr.on("data", (d) => (serverOutput += d));

  const ready = await waitForServer(BASE_URL + "/", 30_000);
  if (!ready) {
    console.error("FAIL: server did not become ready within 30s.");
    console.error(serverOutput);
    await killServerGroup(server);
    process.exit(1);
  }

  console.log(`==> Running ${CONCURRENCY} concurrent workers against ${ROUTES.join(", ")} for ${DURATION_SECONDS}s`);
  const results = [];
  const stopAt = Date.now() + DURATION_SECONDS * 1000;
  await Promise.all(Array.from({ length: CONCURRENCY }, () => runWorker(results, stopAt)));

  await killServerGroup(server);

  console.log("");
  console.log("==> Results by route");
  let anyFailures = false;
  for (const route of ROUTES) {
    const rows = results.filter((r) => r.route === route);
    const failures = rows.filter((r) => !r.ok);
    const latencies = rows.filter((r) => r.ok).map((r) => r.ms).sort((a, b) => a - b);
    const throughput = rows.length / DURATION_SECONDS;
    console.log(
      `${route.padEnd(10)} requests=${rows.length.toString().padStart(5)}  failures=${failures.length}  ` +
        `throughput=${throughput.toFixed(1)}/s  p50=${percentile(latencies, 50)?.toFixed(1)}ms  ` +
        `p95=${percentile(latencies, 95)?.toFixed(1)}ms  p99=${percentile(latencies, 99)?.toFixed(1)}ms`,
    );
    if (failures.length > 0) {
      anyFailures = true;
      const sample = failures.slice(0, 3).map((f) => f.error ?? `HTTP ${f.status}`);
      console.log(`  sample failures: ${sample.join("; ")}`);
    }
  }

  console.log("");
  if (anyFailures) {
    console.error("FAIL: at least one request failed (5xx or network error) under concurrent load.");
    process.exit(1);
  }
  console.log(`PASS: ${results.length} requests, 0 failures, across ${DURATION_SECONDS}s at concurrency ${CONCURRENCY}.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
