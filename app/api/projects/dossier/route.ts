import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../../auth/_supabase";
import { recordAudit } from "../../auth/_audit";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const projectId=new URL(request.url).searchParams.get("projectId");
  const {data,error}=await authDatabase().rpc("get_project_digital_file",{p_token:token,p_project_id:projectId});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar el expediente."},{status:403});
  return NextResponse.json(data);
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  const {data,error}=await authDatabase().rpc("add_project_document",{p_token:token,p_project_id:body.projectId,
    p_category:body.category,p_name:body.name,p_url:body.url,p_description:body.description||"",p_document_date:body.documentDate||null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible agregar el documento."},{status:400});
  await recordAudit(request,token,{action:"DOCUMENTO_PROYECTO_AGREGADO",module:"Expedientes",entityType:"Documento",entityId:data.id,projectId:body.projectId,next:body,reason:body.description||""});
  return NextResponse.json(data);
}
