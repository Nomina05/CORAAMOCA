import { NextResponse } from "next/server";
import { authDatabase, cookieOptions, sessionCookie } from "../_supabase";

export async function POST(request: Request) {
  const { username, password } = await request.json();
  const { data, error } = await authDatabase().rpc("login_app_user", { p_username: username, p_password: password });
  if (error || !data?.token) return NextResponse.json({ error: "Usuario o contraseña incorrectos." }, { status: 401 });
  const response = NextResponse.json({ user: data.user });
  response.cookies.set(sessionCookie, data.token, cookieOptions);
  return response;
}
