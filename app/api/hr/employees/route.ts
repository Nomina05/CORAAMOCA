import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const url=new URL(request.url),year=url.searchParams.get("year"),month=url.searchParams.get("month");
  const {data,error}=await authDatabase().rpc("list_hr_employee_registry",{p_token:token,p_year:year?Number(year):null,p_month:month?Number(month):null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible consultar el registro de empleados."},{status:403});
  return NextResponse.json({employees:data.employees||[],history:data.history||[]});
}
