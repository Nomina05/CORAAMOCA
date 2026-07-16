import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const projectId=new URL(request.url).searchParams.get("projectId");
  const {data,error}=await authDatabase().rpc("list_measurements",{p_token:token,p_project_id:projectId||null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar las cubicaciones."},{status:400});
  return NextResponse.json({measurements:data.measurements});
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  const database=authDatabase();
  const result=body.documentUrl
    ? await database.rpc("add_measurement_document",{p_token:token,p_measurement_id:body.id,p_name:body.documentName,p_url:body.documentUrl})
    : await database.rpc("create_measurement",{p_token:token,p_project_id:body.projectId,p_amount:body.amount,p_progress:body.progress,p_description:body.description});
  if(result.error||!result.data?.success)return NextResponse.json({error:result.data?.error||"No fue posible completar la operación."},{status:400});
  return NextResponse.json(result.data);
}

export async function PATCH(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  const {data,error}=await authDatabase().rpc("transition_measurement_advanced",{
    p_token:token,p_measurement_id:body.id,p_action:body.action||"ADVANCE",p_comments:body.comments||"",
  });
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cambiar el estado de la cubicación."},{status:400});
  return NextResponse.json(data);
}
