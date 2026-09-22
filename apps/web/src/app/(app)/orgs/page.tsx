import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { getUserOrganizations } from "@/lib/auth/org";
import { CreateOrganizationForm } from "./create-organization-form";

export const metadata: Metadata = { title: "Organizations" };

export default async function OrganizationsPage() {
  const user = await requireUser();
  const memberships = await getUserOrganizations(user.id);

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Organizations</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Group learners under an instructor/team-owner/org-admin hierarchy, separate from platform roles. An
        instructor can see their org members&apos; real progress -- graded quiz/lab/CTF/investigation results,
        not a self-reported checklist.
      </p>

      {memberships.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {memberships.map(({ organization, role }) => (
            <li key={organization.id}>
              <Link
                href={`/orgs/${organization.id}`}
                className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
              >
                <div>
                  <p className="text-sm font-medium text-foreground">{organization.name}</p>
                  <p className="text-xs text-foreground-subtle">{organization.slug}</p>
                </div>
                <span className="shrink-0 rounded-full bg-accent-muted px-2.5 py-0.5 text-xs font-medium text-accent">
                  {role.replace("_", " ")}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-center text-sm text-foreground-muted">
          You&apos;re not a member of any organization yet.
        </div>
      )}

      <CreateOrganizationForm />
    </div>
  );
}
