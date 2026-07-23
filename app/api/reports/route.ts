import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const value=new URL(request.url).searchParams.get("year");
  const database=authDatabase();
  const {data,error}=await database.rpc("get_institutional_reports",{p_token:token,p_year:value?Number(value):null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible generar los reportes."},{status:403});
  let publicInvestment=Array.isArray(data.publicInvestment)?data.publicInvestment:[];
  const projectsResult=await database.rpc("list_technical_projects",{p_token:token});
  const projects=Array.isArray(projectsResult.data?.projects)?projectsResult.data.projects:[];
  if(projects.length>0){
    publicInvestment=projects
      .filter((project:Record<string,unknown>)=>!value||Number(project.project_year)===Number(value))
      .map((project:Record<string,unknown>)=>{const fixedAsset=String(project.fixed_assets||"").trim();const normalizedFixedAsset=fixedAsset.normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase();const isAsset=/\bactivos?\s+fijos?\b/.test(normalizedFixedAsset);const isGenericAsset=/^activos?\s+fijos?$/.test(normalizedFixedAsset);const registeredType=project.work_type||project.work_name;return {
        id:project.id,record_type:isAsset?"ACTIVO_FIJO":"OBRA",snip_code:project.snip_code||"",work_type:isAsset&&!isGenericAsset?fixedAsset:registeredType||(isAsset?"Tipo de activo no especificado":"Tipo de obra no especificado"),
        work_name:project.work_name||"Obra sin nombre",municipality:project.municipality||"",district:project.district||"",
        location_name:project.district||project.municipality||"Sin ubicación",
        location_type:project.district?"Distrito":"Municipio",sector:project.sector||"Sin sector",
        population:Number(project.population||0),linear_meters:Number(project.linear_meters||0),
        budgeted_amount:Number(project.budgeted_amount||0),appropriation_amount:Number(project.appropriation_amount||0),committed_amount:Number(project.committed_amount||0),awarded_amount:Number(project.awarded_amount||0),advance_20_amount:Number(project.advance_20_amount||0),
        measurement_status:project.measurement_status||"Pendiente",total_measured:Number(project.total_measured||0),
        total_paid:Number(project.total_paid||0),work_status:project.work_status||"Sin estatus",
        work_progress:Number(project.work_progress||0),
        project_year:Number(project.project_year||0),
      }});
  }
  return NextResponse.json({...data,publicInvestment});
}
