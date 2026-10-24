import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const q=new URL(request.url).searchParams;
 const validationId=q.get("validation");
 const {data,error}=validationId?await authDatabase().rpc("list_hr_payroll_validation",{p_token:token,p_batch_id:validationId}):await authDatabase().rpc("list_hr_payroll_processing",{p_token:token,p_year:Number(q.get("year")||2026),p_month:Number(q.get("month")||1),p_type:q.get("type")||"NOMINA",p_program:Number(q.get("program")||1),p_execution_fund:q.get("fund")||null,p_subproduct:q.get("subproduct")?Number(q.get("subproduct")):null,p_activity:q.get("activity")?Number(q.get("activity")):null,p_account_code:q.get("account")||null});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible consultar la nómina."},{status:403});
 return NextResponse.json(data);
}
export async function POST(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const body=await request.json();
 if(body.action==="manual-isr"){
  const {data,error}=await authDatabase().rpc("update_hr_payroll_line_isr",{p_token:token,p_line_id:body.line_id,p_isr:Number(body.isr||0)});
  if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:400});return NextResponse.json(data);
 }
 if(body.action==="validate"||body.action==="close"||body.action==="reopen"){
  const rpc=body.action==="validate"?"validate_hr_payroll_batch":body.action==="close"?"close_hr_payroll_batch":"reopen_hr_payroll_batch";
  const {data,error}=await authDatabase().rpc(rpc,{p_token:token,p_batch_id:body.batch_id,...(body.action==="reopen"?{p_reason:String(body.reason||"")}:{})});
  if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:400});return NextResponse.json(data);
 }
 const {data,error}=await authDatabase().rpc("generate_hr_payroll",{p_token:token,p_year:Number(body.year),p_month:Number(body.month),p_type:body.type,p_account_code:body.account_code||"",p_program:Number(body.program||1),p_execution_fund:String(body.execution_fund||"30"),p_subproduct:Number(body.subproduct||0),p_activity:Number(body.activity||1)});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible generar la nómina."},{status:400});return NextResponse.json(data);
}
