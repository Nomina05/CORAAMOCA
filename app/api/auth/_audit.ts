import { createHash } from "node:crypto";
import { authDatabase } from "./_supabase";

export async function recordAudit(request:Request,token:string,input:{
  action:string;module:string;entityType:string;entityId?:string|null;projectId?:string|null;measurementId?:string|null;
  previous?:unknown;next?:unknown;reason?:string;
}){
  try{
    const forwarded=request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    const ip=forwarded||request.headers.get("x-real-ip")||"";
    const fingerprint=createHash("sha256").update(token).digest("hex").slice(0,24);
    await authDatabase().rpc("record_complete_audit",{
      p_token:token,p_action:input.action,p_module:input.module,p_entity_type:input.entityType,
      p_entity_id:input.entityId||null,p_project_id:input.projectId||null,p_measurement_id:input.measurementId||null,
      p_previous:input.previous??null,p_new:input.next??null,p_reason:input.reason||"",p_ip:ip,p_session:fingerprint,
    });
  }catch(error){
    console.error("No fue posible registrar la auditoría institucional.",error);
  }
}
