import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const url=new URL(request.url),year=url.searchParams.get("year"),month=url.searchParams.get("month");
  const {data,error}=await authDatabase().rpc("list_hr_employee_registry",{p_token:token,p_year:year?Number(year):null,p_month:month?Number(month):null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible consultar el registro de empleados."},{status:403});
  const session=await authDatabase().rpc("get_app_session",{p_token:token});
  const user=session.data?.user as {role?:string;permissions?:Record<string,boolean>}|undefined;
  const admin=user?.role==="Administrador",permissions=user?.permissions||{};
  const employees=(data.employees||[]).map((employee:Record<string,unknown>)=>{
    const row={...employee};
    if(!admin&&!permissions.ver_datos_personales)for(const key of ["document_number","birth_date","phone","cell_phone","landline_phone","driver_license","blood_type","home_address","bank_account","academic_level"])delete row[key];
    if(!admin&&!permissions.ver_salarios)for(const key of ["monthly_salary","benefits","payroll_assignments"])delete row[key];
    if(!admin&&!permissions.ver_descuentos)delete row.deductions;
    return row;
  });
  const history=(data.history||[]).map((entry:Record<string,unknown>)=>{const row={...entry};if(!admin&&!permissions.ver_salarios)delete row.monthly_salary;if(!admin&&!permissions.ver_datos_personales)delete row.document_number;return row});
  return NextResponse.json({employees,history});
}
