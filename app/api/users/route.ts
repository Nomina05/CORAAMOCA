import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase, sessionCookie } from "../auth/_supabase";

export async function GET() {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "No autorizado." }, { status: 401 });
  const { data, error } = await authDatabase().rpc("admin_list_users", { p_token: token });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No autorizado." }, { status: 403 });
  return NextResponse.json({ users: data.users });
}

export async function POST(request: Request) {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "No autorizado." }, { status: 401 });
  const body = await request.json();
  const { data, error } = await authDatabase().rpc("admin_create_user", {
    p_token: token, p_username: body.username, p_temp_password: body.password,
    p_full_name: body.fullName, p_area: body.area, p_role: body.role, p_permissions: body.permissions || {},
  });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible crear el usuario." }, { status: 400 });
  return NextResponse.json({ success: true, user: data.user });
}

export async function PATCH(request: Request) {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "No autorizado." }, { status: 401 });
  const { id, role, area, active, permissions } = await request.json();
  const { data, error } = permissions
    ? await authDatabase().rpc("admin_set_user_permissions", { p_token: token, p_user_id: id, p_permissions: permissions })
    : await authDatabase().rpc("admin_update_user", { p_token: token, p_user_id: id, p_role: role, p_area: area, p_active: Boolean(active) });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible actualizar el usuario." }, { status: 400 });
  return NextResponse.json({ success: true });
}
