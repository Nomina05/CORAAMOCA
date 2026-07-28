import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
 const session=(await cookies()).get(sessionCookie)?.value;
 if(!session)return NextResponse.json({error:"No autorizado."},{status:401});
 const value=new URL(request.url).searchParams.get("year");
 const year=value&&value!=="ALL"?Number(value):null;
 const {data,error}=await authDatabase().rpc("get_hr_case_analytics",{p_token:session,p_year:year});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible generar los indicadores."},{status:403});
 return NextResponse.json(data);
}
