import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../auth/_supabase";
import { recordAudit } from "../auth/_audit";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const requestedYear=new URL(request.url).searchParams.get("year");
  const year=requestedYear==="all"?null:Number(requestedYear||new Date().getFullYear());
  const {data,error}=await authDatabase().rpc("get_budget_management",{p_token:token,p_year:year});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar el presupuesto."},{status:403});
  return NextResponse.json(data);
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  const database=authDatabase();
  const result=body.action==="close"
    ? await database.rpc("close_budget_year",{p_token:token,p_year:body.year,p_notes:body.notes||""})
    : await database.rpc("add_budget_modification",{p_token:token,p_project_id:body.projectId,p_type:body.type,p_amount:body.amount,p_description:body.description,p_reference:body.reference||""});
  if(result.error||!result.data?.success)return NextResponse.json({error:result.data?.error||"No fue posible completar la operación."},{status:400});
  const movementAction=body.type==="APROPIACION"?"REGISTRO_APROPIACION":body.type==="ADJUDICACION"?"REGISTRO_ADJUDICACION":"MODIFICACION_PRESUPUESTARIA";
  await recordAudit(request,token,{action:body.action==="close"?"CIERRE_PRESUPUESTARIO":movementAction,module:"Presupuesto",entityType:body.action==="close"?"Año presupuestario":"Proyecto",entityId:String(body.year||body.projectId||""),projectId:body.projectId||null,next:body,reason:body.notes||body.description||""});
  return NextResponse.json(result.data);
}

export async function PATCH(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  const {data,error}=await authDatabase().rpc("transition_budget_modification",{p_token:token,p_modification_id:body.id,p_action:body.action||"ADVANCE",p_comments:body.comments||""});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cambiar la etapa."},{status:400});
  await recordAudit(request,token,{action:body.action==="RETURN"?"MOVIMIENTO_FINANCIERO_DEVUELTO":"MOVIMIENTO_FINANCIERO_AVANZADO",module:"Presupuesto",entityType:"Movimiento financiero",entityId:body.id,projectId:data.project_id,previous:{status:data.previous_status},next:{status:data.status},reason:body.comments||""});
  return NextResponse.json(data);
}
