"use client";

import {useEffect} from "react";

export default function ErrorPage({error,reset}:{error:Error&{digest?:string};reset:()=>void}){
  useEffect(()=>{
    fetch("/api/system/errors",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({
      source:"Next.js error boundary",code:error.digest||"RENDER_ERROR",message:error.message,
      detail:error.stack||"",path:window.location.pathname,
    })}).catch(()=>undefined);
  },[error]);
  return <main className="system-error"><section><span>INCIDENTE REGISTRADO</span><h1>No fue posible completar esta pantalla.</h1><p>El fallo fue registrado para revisión técnica. Puede intentar nuevamente sin perder su sesión.</p><button onClick={reset}>Reintentar operación</button></section></main>;
}
