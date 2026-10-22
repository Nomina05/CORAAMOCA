import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";
export async function GET(request:Request){const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const q=new URL(request.url).searchParams,{data,error}=await authDatabase().rpc("list_hr_payroll_monthly_comparison",{p_token:token,p_year:Number(q.get("year")||new Date().getFullYear()),p_month:Number(q.get("month")||new Date().getMonth()+1)});if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:403});return NextResponse.json(data)}
