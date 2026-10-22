import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const employee=new URL(request.url).searchParams.get("employee");
 if(!employee)return NextResponse.json({error:"Seleccione un colaborador."},{status:400});
 const {data,error}=await authDatabase().rpc("get_hr_employee_dossier",{p_token:token,p_employee_id:employee});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible abrir el expediente."},{status:403});
 return NextResponse.json(data);
}

export async function POST(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const body=await request.json();
 const {data,error}=await authDatabase().rpc("add_hr_employee_document",{
  p_token:token,p_employee_id:body.employee_id,p_document_type:body.document_type,p_document_name:body.document_name,
  p_document_url:body.document_url,p_description:body.description||"",p_document_date:body.document_date||null
 });
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible agregar el documento."},{status:400});
 return NextResponse.json(data);
}
