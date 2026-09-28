import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { getLocale } from "@/lib/i18n/cookie";
import { pickAnnouncementText } from "@/lib/i18n/announcement-translation";
import type { SkillState } from "@/types/database";

export const metadata: Metadata = { title: "Dashboard" };

export default async function DashboardPage() {
  const user = await requireUser();
  const supabase = await createClient();
  const locale = await getLocale();

  const nowIso = new Date().toISOString();
  const [{ data: profile }, { data: states }, { data: subscription }, { data: announcements }] = await Promise.all([
    supabase.from("profiles").select("display_name, username").eq("id", user.id).single(),
    supabase.from("user_skill_states").select("state"),
    supabase
      .from("subscriptions")
      .select("plan_id, status, plans(name, slug)")
      .eq("subject_type", "user")
      .eq("subject_id", user.id)
      .in("status", ["trialing", "active", "past_due"])
      .maybeSingle(),
    // RLS (announcements_select) already restricts org-scoped rows to orgs
    // this user belongs to -- the published/expiry filters here just make
    // sure a staff/instructor viewer's own draft-preview visibility doesn't
    // leak an unpublished notice into their own dashboard banner.
    supabase
      .from("announcements")
      .select("id, title, body_markdown, published_at")
      .eq("published", true)
      .or(`expires_at.is.null,expires_at.gt.${nowIso}`)
      .order("published_at", { ascending: false })
      .limit(5),
  ]);

  // A second round-trip rather than a join: announcement_translations'
  // own RLS (mirroring announcements_select through the parent row, see
  // 20260922000030_announcement_translations.sql) already scopes this to
  // exactly the rows above, so an `.in()` on their ids is just an
  // efficiency filter, not a second security boundary.
  const { data: translations } =
    announcements && announcements.length > 0
      ? await supabase
          .from("announcement_translations")
          .select("announcement_id, locale, title, body_markdown")
          .in(
            "announcement_id",
            announcements.map((a) => a.id),
          )
      : { data: [] };
  const translationsByAnnouncementId = new Map<string, typeof translations>();
  for (const t of translations ?? []) {
    const existing = translationsByAnnouncementId.get(t.announcement_id) ?? [];
    existing.push(t);
    translationsByAnnouncementId.set(t.announcement_id, existing);
  }

  const counts = new Map<SkillState, number>();
  for (const row of states ?? []) {
    const s = row.state as SkillState;
    counts.set(s, (counts.get(s) ?? 0) + 1);
  }
  const inProgress = (counts.get("LEARNING") ?? 0) + (counts.get("PRACTICING") ?? 0);
  const proven =
    (counts.get("ASSESSED") ?? 0) + (counts.get("DEMONSTRATED") ?? 0) + (counts.get("MASTERED") ?? 0);
  const planName = (subscription?.plans as unknown as { name: string } | null)?.name ?? "Free";

  return (
    <div className="mx-auto max-w-5xl px-6 py-10">
      <h1 className="text-2xl font-semibold text-foreground">
        Welcome back, {profile?.display_name ?? user.email}
      </h1>
      <p className="mt-1 text-sm text-foreground-muted">
        You&apos;re on the <span className="font-medium text-foreground">{planName}</span> plan.
      </p>

      {announcements && announcements.length > 0 && (
        <div className="mt-6 space-y-3">
          {announcements.map((a) => {
            const text = pickAnnouncementText(a, translationsByAnnouncementId.get(a.id) ?? [], locale);
            return (
              <div key={a.id} className="rounded-lg border border-accent/30 bg-accent-muted p-4">
                <p className="text-sm font-medium text-accent">{text.title}</p>
                <p className="mt-1 whitespace-pre-wrap text-sm text-foreground-muted">{text.body_markdown}</p>
              </div>
            );
          })}
        </div>
      )}

      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        <Link
          href="/skills"
          className="rounded-lg border border-border bg-surface p-5 transition-colors hover:border-border-strong"
        >
          <p className="text-xs text-foreground-subtle">Skills in progress</p>
          <p className="mt-1 text-2xl font-semibold text-foreground">{inProgress}</p>
          <p className="mt-3 text-sm text-accent">View skill graph &rarr;</p>
        </Link>
        <Link
          href="/skills"
          className="rounded-lg border border-border bg-surface p-5 transition-colors hover:border-border-strong"
        >
          <p className="text-xs text-foreground-subtle">Skills with proven ability</p>
          <p className="mt-1 text-2xl font-semibold text-foreground">{proven}</p>
          <p className="mt-3 text-sm text-accent">Assessed, demonstrated, or mastered &rarr;</p>
        </Link>
      </div>

      {inProgress === 0 && proven === 0 && (
        <div className="mt-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          You haven&apos;t started building evidence for any skill yet. Head to the{" "}
          <Link href="/skills" className="font-medium text-accent hover:underline">
            skill graph
          </Link>{" "}
          to see everything this platform tracks.
        </div>
      )}
    </div>
  );
}
