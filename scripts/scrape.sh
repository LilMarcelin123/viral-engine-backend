#!/usr/bin/env bash
# =====================================================================
# Scrapeo manual de Viral Engine
#
# Cada corrida de Apify cuesta. Este script es el ÚNICO disparador: no hay
# tarea programada ni botón en la aplicación.
#
# USO
#   ./scrape.sh ver              # qué se scrapearía, sin gastar nada
#   ./scrape.sh correr           # todas las campañas activas
#   ./scrape.sh correr 3         # solo la campaña 3
#   ./scrape.sh corridas         # historial y costo
#   ./scrape.sh sospechosas      # publicaciones cuyo autor no coincide
#
# CONFIGURACIÓN (variables de entorno)
#   VE_API    url del backend   (por defecto la de producción)
#   VE_USER   correo del admin
#   VE_PASS   contraseña del admin
#
#   export VE_USER=tucorreo@dominio.com
#   export VE_PASS='tu-password'
# =====================================================================
set -euo pipefail

API="${VE_API:-https://viral-engine-backend-production.up.railway.app}"
ESPERA="${VE_ESPERA:-20}"      # segundos entre intentos de recolección
INTENTOS="${VE_INTENTOS:-30}"  # máximo de intentos (30 x 20s = 10 min)

if [[ -z "${VE_USER:-}" || -z "${VE_PASS:-}" ]]; then
  echo "Falta configurar VE_USER y VE_PASS." >&2
  echo "  export VE_USER=tucorreo@dominio.com" >&2
  echo "  export VE_PASS='tu-password'" >&2
  exit 1
fi

command -v jq >/dev/null || { echo "Necesitas jq: brew install jq" >&2; exit 1; }

login() {
  local r
  r=$(curl -sS -X POST "$API/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$VE_USER\",\"password\":\"$VE_PASS\"}")
  TOKEN=$(echo "$r" | jq -r '.token // empty')
  if [[ -z "$TOKEN" ]]; then
    echo "No se pudo iniciar sesión: $(echo "$r" | jq -r '.message // .')" >&2
    exit 1
  fi
}

api() {  # api METODO RUTA
  curl -sS -X "$1" "$API$2" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
}

cmd="${1:-ver}"
campaign="${2:-}"
qs=""
[[ -n "$campaign" ]] && qs="?campaign=$campaign"

login

case "$cmd" in

  ver)
    echo "== Publicaciones pendientes de scrapear =="
    api GET "/scrape/pendientes$qs" | jq
    ;;

  corridas)
    echo "== Últimas corridas =="
    api GET "/scrape/corridas" | jq -r '
      ["ID","PLATAFORMA","ESTADO","PEDIDOS","RECIBIDOS","USD","INICIO"],
      (.[] | [.id, (.plataforma//"-"), .estado, .items_solicitados,
              .items_recibidos, (.costo_usd//0), .iniciado_at])
      | @tsv' | column -t -s $'\t'
    ;;

  sospechosas)
    echo "== Publicaciones cuyo autor NO coincide con la cuenta registrada =="
    api GET "/scrape/sospechosas" | jq -r '
      if length == 0 then "Ninguna." else
      (["CLIP","EDITOR","REGISTRADA","DETECTADO","ESTADO","LINK"],
       (.[] | [.clip_id, .editor, (.cuenta_registrada//"-"),
               (.autor_detectado//"-"), .estado_qa, .link])
       | @tsv) end' | column -t -s $'\t'
    ;;

  correr)
    echo "== Iniciando corridas =="
    inicio=$(api POST "/scrape/iniciar$qs")
    echo "$inicio" | jq

    if echo "$inicio" | jq -e 'any(.[]; .estado == "EJECUTANDO")' >/dev/null 2>&1; then
      echo
      echo "== Esperando a Apify (hasta $((ESPERA * INTENTOS / 60)) min) =="
      for ((i=1; i<=INTENTOS; i++)); do
        sleep "$ESPERA"
        res=$(api POST "/scrape/recolectar")

        if echo "$res" | jq -e 'all(.[]; .estado != "EJECUTANDO")' >/dev/null 2>&1; then
          echo
          echo "== Resultado =="
          echo "$res" | jq
          echo
          echo "== Revisión de propiedad =="
          api GET "/scrape/sospechosas" | jq -r \
            'if length == 0 then "Sin publicaciones sospechosas."
             else "\(length) publicación(es) con autor distinto al registrado. Corre: ./scrape.sh sospechosas" end'
          echo
          echo "Listo. Ya puedes calcular pagos en las campañas afectadas."
          exit 0
        fi
        printf '  intento %d/%d — Apify sigue trabajando\n' "$i" "$INTENTOS"
      done

      echo "Se agotó la espera. Las corridas siguen abiertas en Apify." >&2
      echo "Vuelve a intentar más tarde con: ./scrape.sh recolectar" >&2
      exit 2
    fi
    ;;

  recolectar)
    echo "== Recolectando corridas abiertas =="
    api POST "/scrape/recolectar" | jq
    ;;

  *)
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
