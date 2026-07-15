import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase, sessionCookie } from "../_supabase";

export async function POST(request: Request) {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "Sesión no válida." }, { status: 401 });
  const { password } = await request.json();
  const { data, error } = await authDatabase().rpc("change_own_password", { p_token: token, p_new_password: password });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible cambiar la contraseña." }, { status: 400 });
  return NextResponse.json({ success: true, user: data.user });
}
