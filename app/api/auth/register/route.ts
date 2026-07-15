import { NextResponse } from "next/server";
import { authDatabase, cookieOptions, sessionCookie } from "../_supabase";

export async function POST(request: Request) {
  const { username, password, fullName, area } = await request.json();
  const database = authDatabase();
  const { data: created, error: createError } = await database.rpc("register_app_user", { p_username: username, p_password: password, p_full_name: fullName, p_area: area });
  if (createError || !created?.success) return NextResponse.json({ error: created?.error || "No fue posible crear el usuario." }, { status: 400 });
  const { data, error } = await database.rpc("login_app_user", { p_username: username, p_password: password });
  if (error || !data?.token) return NextResponse.json({ error: "Cuenta creada. Inicia sesión para continuar." }, { status: 201 });
  const response = NextResponse.json({ user: data.user });
  response.cookies.set(sessionCookie, data.token, cookieOptions);
  return response;
}
