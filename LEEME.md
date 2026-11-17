# Kontrola

1. Instala Node.js 18 o superior.
2. En esta carpeta: `npm install`
3. `npm run dev` y abre http://localhost:5173
4. Para probarla en el celular (misma red wifi): abre la dirección "Network" que muestra la terminal.

Cuentas demo (clave entre paréntesis): Súper Admin 1-9 (1234), Admin 2-7 (1234),
trabajadores 11.111.111-1 (1111), 12.345.678-5 (2222), 9.876.543-3 (3333).

La cámara del escáner exige HTTPS o localhost. Para publicar: `npm run build` y sube la carpeta `dist`
a Vercel o Netlify (agrega las variables VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY).
