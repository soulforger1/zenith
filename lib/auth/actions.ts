"use server";

import { timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { createSessionToken, SESSION_COOKIE_NAME, sessionCookieOptions } from "./session";

export type LoginState = { error?: string } | undefined;

// Constant-time string compare so a wrong guess can't be timed to leak how
// many leading characters matched. .env.local never leaves this machine and
// isn't committed, so there's no need to hash APP_PASSWORD at rest.
function safeCompare(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    timingSafeEqual(bufA, bufA); // keep timing consistent with the match path
    return false;
  }
  return timingSafeEqual(bufA, bufB);
}

export async function loginAction(_prevState: LoginState, formData: FormData): Promise<LoginState> {
  const password = formData.get("password");
  if (typeof password !== "string" || password.length === 0) {
    return { error: "Password is required." };
  }

  const expected = process.env.APP_PASSWORD;
  if (!expected) {
    throw new Error("APP_PASSWORD is not set. Copy .env.example to .env.local and fill it in.");
  }

  if (!safeCompare(password, expected)) {
    return { error: "Incorrect password." };
  }

  const token = await createSessionToken();
  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, token, sessionCookieOptions);

  redirect("/spaces");
}

export async function logoutAction(): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
  redirect("/login");
}
