"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { isSupportedLocale } from "./locales";
import { LOCALE_COOKIE_NAME } from "./cookie";

const ONE_YEAR_SECONDS = 60 * 60 * 24 * 365;

export async function setLocaleAction(locale: string, currentPath: string) {
  if (!isSupportedLocale(locale)) return;
  const store = await cookies();
  store.set(LOCALE_COOKIE_NAME, locale, {
    path: "/",
    maxAge: ONE_YEAR_SECONDS,
    sameSite: "lax",
  });
  revalidatePath(currentPath);
}
