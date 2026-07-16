import { NextResponse } from "next/server";
import { authDatabase, cookieOptions, sessionCookie } from "../_supabase";

export async function POST(request: Request) {
  const { username, password } = await request.json();
  const { data, error } = await authDatabase().rpc("login_app_user", { p_username: username, p_password: password });
  if (error || !data?.token) {
    const status = data?.code === "SUSPENDED" ? 403 : data?.code === "LOCKED" ? 423 : 401;
    return NextResponse.json({ error: data?.error || "Usuario o contraseña incorrectos.", code: data?.code }, { status });
  }
  const response = NextResponse.json({ user: data.user });
  response.cookies.set(sessionCookie, data.token, cookieOptions);
  return response;
}
