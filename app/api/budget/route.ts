import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const year=Number(new URL(request.url).searchParams.get("year")||new Date().getFullYear());
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
  return NextResponse.json(result.data);
}
