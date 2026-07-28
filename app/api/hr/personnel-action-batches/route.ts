import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const {data,error}=await authDatabase().rpc("list_hr_personnel_action_batches",{p_token:token});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:403});
 return NextResponse.json({items:data.items||[]});
}

export async function POST(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const {data,error}=await authDatabase().rpc("create_hr_personnel_action_batch",{p_token:token,p_data:await request.json()});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:400});
 return NextResponse.json(data);
}
