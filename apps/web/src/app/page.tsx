import Link from "next/link";
import { ButtonLink } from "@/components/ui/button-link";
import { getCurrentUser } from "@/lib/auth/session";

export default async function HomePage() {
  const user = await getCurrentUser();

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex h-16 items-center justify-between border-b border-border px-6">
        <span className="font-mono text-base font-semibold tracking-tight">
          iCore<span className="text-accent">Pen</span>
        </span>
        <nav className="flex items-center gap-3">
          {user ? (
            <ButtonLink href="/dashboard" size="sm">
              Dashboard
            </ButtonLink>
          ) : (
            <>
              <Link href="/login" className="text-sm font-medium text-foreground-muted hover:text-foreground">
                Log in
              </Link>
              <ButtonLink href="/signup" size="sm">
                Sign up
              </ButtonLink>
            </>
          )}
        </nav>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center px-6 py-24 text-center">
        <p className="font-mono text-xs uppercase tracking-widest text-accent">
          Learn &rarr; Investigate &rarr; Practice &rarr; Prove
        </p>
        <h1 className="mt-4 max-w-2xl text-4xl font-semibold tracking-tight text-foreground sm:text-5xl">
          A cybersecurity training platform that tracks real skill, not course completion.
        </h1>
        <p className="mt-5 max-w-xl text-base text-foreground-muted">
          Every skill on the platform moves through a state machine backed by evidence: theory,
          quizzes, guided labs, independent labs, CTF challenges, assessments, and retests. Opening
          a lesson never counts as mastery.
        </p>
        <div className="mt-8 flex items-center gap-3">
          <ButtonLink href="/signup" size="lg">
            Start learning
          </ButtonLink>
          <ButtonLink href="/login" size="lg" variant="secondary">
            Log in
          </ButtonLink>
        </div>
      </main>

      <footer className="border-t border-border px-6 py-6 text-center text-xs text-foreground-subtle">
        Authorized security training only. All labs, targets, and scanning run in isolated,
        platform-controlled environments.
      </footer>
    </div>
  );
}
