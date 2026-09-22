import Link from "next/link";
import { requireAdmin } from "@/lib/auth/session";

const ADMIN_SECTIONS = [
  { href: "/admin", label: "Overview" },
  { href: "/admin/paths", label: "Learning Paths" },
  { href: "/admin/labs", label: "Labs" },
  { href: "/admin/quizzes", label: "Quizzes" },
  { href: "/admin/ctf", label: "CTF Challenges" },
  { href: "/admin/investigations", label: "Investigations" },
];

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  // The real enforcement point: re-verifies admin via user_roles (RLS-backed),
  // not just the nav link's conditional rendering or the proxy's redirect.
  await requireAdmin();

  return (
    <div className="mx-auto max-w-6xl px-6 py-10">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-foreground">Admin</h1>
        <span className="rounded-full border border-accent/30 bg-accent-muted px-2.5 py-0.5 text-xs font-medium text-accent">
          Admin access
        </span>
      </div>
      <div className="flex gap-6">
        <nav className="w-48 shrink-0 space-y-1">
          {ADMIN_SECTIONS.map((section) => (
            <Link
              key={section.href}
              href={section.href}
              className="block rounded-md px-3 py-2 text-sm font-medium text-foreground-muted hover:bg-surface hover:text-foreground"
            >
              {section.label}
            </Link>
          ))}
        </nav>
        <div className="min-w-0 flex-1">{children}</div>
      </div>
    </div>
  );
}
