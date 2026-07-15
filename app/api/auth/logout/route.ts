import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase, sessionCookie } from "../_supabase";

export async function POST() {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (token) await authDatabase().rpc("logout_app_session", { p_token: token });
  const response = NextResponse.json({ success: true });
  response.cookies.set(sessionCookie, "", { path: "/", maxAge: 0 });
  return response;
}
