import type { en } from "./en";

/**
 * Spanish. Deliberately typed as Partial<...> -- a real dictionary is
 * allowed to lag the English one while a key is being translated;
 * translate() (see ../translate.ts) falls back to English for any key
 * missing here rather than rendering nothing or throwing.
 */
export const es: Partial<Record<keyof typeof en, string>> = {
  "landing.nav.dashboard": "Panel",
  "landing.nav.login": "Iniciar sesión",
  "landing.nav.signup": "Registrarse",
  "landing.tagline": "Aprender → Investigar → Practicar → Demostrar",
  "landing.heading":
    "Una plataforma de formación en ciberseguridad que mide la habilidad real, no la finalización de cursos.",
  "landing.subheading":
    "Cada habilidad de la plataforma avanza a través de una máquina de estados respaldada por evidencia: teoría, cuestionarios, laboratorios guiados, laboratorios independientes, retos CTF, evaluaciones y reintentos. Abrir una lección nunca cuenta como dominio.",
  "landing.cta.startLearning": "Empezar a aprender",
  "landing.cta.login": "Iniciar sesión",
  "landing.footer":
    "Solo para formación de seguridad autorizada. Todos los laboratorios, objetivos y análisis se ejecutan en entornos aislados controlados por la plataforma.",

  "settings.language.heading": "Idioma",
  "settings.language.description":
    "El idioma que elijas aquí se guarda para las páginas que admiten traducción (actualmente: la página pública de inicio). El resto de la aplicación sigue estando solo en inglés por ahora.",
  "settings.language.en": "English",
  "settings.language.es": "Español",
};
