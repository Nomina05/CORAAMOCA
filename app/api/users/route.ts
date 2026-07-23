import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase, sessionCookie } from "../auth/_supabase";
import { recordAudit } from "../auth/_audit";

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
  const database=authDatabase();
  const { data, error } = await database.rpc("admin_create_employee_user", {
    p_token: token, p_employee_id: body.employeeId, p_username: body.username, p_temp_password: body.password,
    p_role: body.role, p_permissions: body.permissions || {},
  });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible crear el usuario." }, { status: 400 });
  await recordAudit(request,token,{action:"USUARIO_CREADO",module:"Usuarios",entityType:"Usuario",entityId:data.user?.id,next:{username:body.username,employeeId:body.employeeId,role:body.role}});
  return NextResponse.json({ success: true, user:data.user });
}

export async function PATCH(request: Request) {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "No autorizado." }, { status: 401 });
  const { id, role, area, department, active, suspensionReason, permissions, employeeId } = await request.json();
  const database = authDatabase();
  if(employeeId){
    const {data,error}=await database.rpc("admin_link_user_employee",{p_token:token,p_user_id:id,p_employee_id:employeeId});
    if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible vincular el empleado."},{status:400});
    await recordAudit(request,token,{action:"EMPLEADO_VINCULADO",module:"Usuarios",entityType:"Usuario",entityId:id,next:{employeeId}});
    return NextResponse.json({success:true,user:data.user});
  }
  let result = permissions
    ? await database.rpc("admin_set_user_permissions", { p_token: token, p_user_id: id, p_permissions: permissions })
    : await database.rpc("admin_update_user", {
        p_token: token, p_user_id: id, p_role: role, p_area: area,
        p_active: Boolean(active), p_department: department || "",
        p_suspension_reason: suspensionReason || "",
      });
  // Compatibilidad durante el despliegue: permite aplicar primero la app y luego la migración SQL.
  if (!permissions && result.error?.message?.includes("function public.admin_update_user")) {
    result = await database.rpc("admin_update_user", {
      p_token: token, p_user_id: id, p_role: role, p_area: area, p_active: Boolean(active),
    });
  }
  const { data, error } = result;
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible actualizar el usuario." }, { status: 400 });
  await recordAudit(request,token,{action:permissions?"PERMISOS_MODIFICADOS":active?"USUARIO_MODIFICADO":"USUARIO_SUSPENDIDO",module:"Usuarios",entityType:"Usuario",entityId:id,next:{role,area,department,active,permissions},reason:suspensionReason||""});
  return NextResponse.json({ success: true });
}
