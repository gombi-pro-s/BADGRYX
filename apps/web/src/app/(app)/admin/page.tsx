import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Admin" };

export default async function AdminOverviewPage() {
  const supabase = await createClient();
  const [paths, labs, quizzes, challenges, skills] = await Promise.all([
    supabase.from("learning_paths").select("id, published"),
    supabase.from("labs").select("id, published"),
    supabase.from("quizzes").select("id, published"),
    supabase.from("ctf_challenges").select("id, published"),
    supabase.from("skills").select("id"),
  ]);

  const cards = [
    { label: "Learning paths", href: "/admin/paths", data: paths.data },
    { label: "Labs", href: "/admin/labs", data: labs.data },
    { label: "Quizzes", href: "/admin/quizzes", data: quizzes.data },
    { label: "CTF challenges", href: "/admin/ctf", data: challenges.data },
  ];

  return (
    <div>
      <p className="mb-6 text-sm text-foreground-muted">
        {skills.data?.length ?? 0} skills in the catalog. Content below feeds the grading pipeline
        and Skill Graph directly once published.
      </p>
      <div className="grid gap-4 sm:grid-cols-2">
        {cards.map((card) => {
          const total = card.data?.length ?? 0;
          const published = card.data?.filter((d) => "published" in d && d.published).length ?? 0;
          return (
            <Link
              key={card.href}
              href={card.href}
              className="rounded-lg border border-border bg-surface p-5 transition-colors hover:border-border-strong"
            >
              <p className="text-xs text-foreground-subtle">{card.label}</p>
              <p className="mt-1 text-2xl font-semibold text-foreground">{total}</p>
              <p className="mt-1 text-xs text-foreground-subtle">{published} published</p>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
