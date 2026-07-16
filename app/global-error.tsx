"use client";

export default function GlobalError({reset}:{error:Error&{digest?:string};reset:()=>void}){
  return <html lang="es"><body><main className="system-error"><section><span>SISTEMA INSTITUCIONAL</span><h1>Servicio temporalmente no disponible.</h1><p>Actualice la página o reintente en unos segundos.</p><button onClick={reset}>Reintentar</button></section></main></body></html>;
}
