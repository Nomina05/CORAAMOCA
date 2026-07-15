import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase, sessionCookie } from "../_supabase";

export async function GET() {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ user: null }, { status: 401 });
  const { data, error } = await authDatabase().rpc("get_app_session", { p_token: token });
  if (error || !data?.user) return NextResponse.json({ user: null }, { status: 401 });
  return NextResponse.json({ user: data.user });
}
