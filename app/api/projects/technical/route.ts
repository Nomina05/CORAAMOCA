import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase, sessionCookie } from "../../auth/_supabase";
import { recordAudit } from "../../auth/_audit";

export async function GET() {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "No autorizado." }, { status: 401 });
  const { data, error } = await authDatabase().rpc("list_technical_projects", { p_token: token });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible cargar los proyectos." }, { status: 400 });
  return NextResponse.json({ projects: data.projects });
}

export async function POST(request: Request) {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "No autorizado." }, { status: 401 });
  const { id, ...project } = await request.json();
  const database = authDatabase();
  const session = await database.rpc("get_app_session", { p_token: token });
  const user = session.data?.user;
  if (session.error || !user) return NextResponse.json({ error: "Sesión no válida." }, { status: 401 });

  const requiredPermission = id ? "editar_proyectos_tecnicos" : "crear_proyectos_tecnicos";
  if (user.role !== "Administrador" && !user.permissions?.[requiredPermission]) {
    return NextResponse.json(
      { error: id ? "No posee permiso para editar proyectos." : "No posee permiso para crear proyectos." },
      { status: 403 }
    );
  }

  const { data, error } = await database.rpc("save_technical_project", {
    p_token: token,
    p_project_id: id || null,
    p_data: project
  });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible guardar el proyecto." }, { status: 400 });

  const projectId = data.id;
  const paymentResult = await database.rpc("set_project_fixed_asset_payment", {
    p_token: token,
    p_project_id: projectId,
    p_amount: Number(project.fixed_asset_paid_amount || 0)
  });
  if (paymentResult.error || !paymentResult.data?.success) {
    return NextResponse.json({ error: paymentResult.data?.error || "El proyecto se guardó, pero no fue posible actualizar el pago de activos fijos." }, { status: 400 });
  }
  const commitmentResult = await database.rpc("set_project_financial_commitments", {
    p_token: token,
    p_project_id: projectId,
    p_committed: Number(project.committed_amount || 0),
    p_advance: Number(project.advance_20_amount || 0),
  });
  if (commitmentResult.error || !commitmentResult.data?.success) {
    return NextResponse.json({ error: commitmentResult.data?.error || "El proyecto se guardó, pero no fue posible actualizar sus compromisos financieros." }, { status: 400 });
  }
  const classificationResult = await database.rpc("set_project_administrative_classification", {
    p_token: token,
    p_project_id: projectId,
    p_funding_source: project.funding_source || "",
    p_work_type: project.work_type || "",
  });
  if (classificationResult.error || !classificationResult.data?.success) {
    return NextResponse.json({ error: classificationResult.data?.error || "El proyecto se guardó, pero no fue posible actualizar su clasificación administrativa." }, { status: 400 });
  }
  const deadlineResult = await database.rpc("set_project_planned_end_date", {
    p_token: token,
    p_project_id: projectId,
    p_date: project.planned_end_date || null,
  });
  if (deadlineResult.error || !deadlineResult.data?.success) {
    return NextResponse.json({ error: deadlineResult.data?.error || "El proyecto se guardó, pero no fue posible actualizar su fecha prevista." }, { status: 400 });
  }
  await database.rpc("record_project_change", {
    p_token: token,
    p_project_id: projectId,
    p_action: id ? "UPDATE" : "CREATE",
  });
  await recordAudit(request,token,{action:id?"PROYECTO_MODIFICADO":"PROYECTO_CREADO",module:"Proyectos",entityType:"Proyecto",entityId:projectId,projectId,next:project,reason:project.change_reason||""});
  return NextResponse.json({ success: true, id: projectId });
}
