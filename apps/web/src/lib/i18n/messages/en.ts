/**
 * The canonical English dictionary -- every key that exists anywhere MUST
 * exist here, since translate() falls back to this dictionary whenever a
 * non-English one is missing a key. See translate.ts.
 */
export const en = {
  "landing.nav.dashboard": "Dashboard",
  "landing.nav.login": "Log in",
  "landing.nav.signup": "Sign up",
  "landing.tagline": "Learn → Investigate → Practice → Prove",
  "landing.heading": "A cybersecurity training platform that tracks real skill, not course completion.",
  "landing.subheading":
    "Every skill on the platform moves through a state machine backed by evidence: theory, quizzes, guided labs, independent labs, CTF challenges, assessments, and retests. Opening a lesson never counts as mastery.",
  "landing.cta.startLearning": "Start learning",
  "landing.cta.login": "Log in",
  "landing.footer":
    "Authorized security training only. All labs, targets, and scanning run in isolated, platform-controlled environments.",

  "settings.language.heading": "Language",
  "settings.language.description":
    "Choosing a language here is saved for the pages that support translation (currently: the public landing page). The rest of the app is English-only for now.",
  "settings.language.en": "English",
  "settings.language.es": "Español",
} satisfies Record<string, string>;
