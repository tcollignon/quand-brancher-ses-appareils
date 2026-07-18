#!/usr/bin/env bash
set -euo pipefail

: "${RTE_CLIENT_ID:?missing RTE_CLIENT_ID}"
: "${RTE_CLIENT_SECRET:?missing RTE_CLIENT_SECRET}"

TOKEN=$(curl -sf -u "${RTE_CLIENT_ID}:${RTE_CLIENT_SECRET}" \
  -X POST "https://digital.iservices.rte-france.com/token/oauth/" \
  | jq -r '.access_token')

if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
  echo "Failed to obtain OAuth2 token from RTE" >&2
  exit 1
fi

RESPONSE=$(curl -sf -H "Authorization: Bearer ${TOKEN}" \
  "https://digital.iservices.rte-france.com/open_api/wholesale_market/v3/france_power_exchanges")

FETCHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p data

NEW_PRICES=$(echo "${RESPONSE}" | jq -c '[
  .france_power_exchanges[]?.values[]?
  | select(.price != null)
  | { start: .start_date, end: .end_date, price: .price }
]')

EXISTING_PRICES="[]"
if [ -f data/spot-prices.json ]; then
  EXISTING_PRICES=$(jq -c '.prices // []' data/spot-prices.json)
fi

# L'API RTE ne renvoie jamais qu'un seul jour à la fois (aujourd'hui avant 13h CET, demain
# après 14h) : un simple écrasement effacerait donc la journée déjà connue à chaque nouvelle
# récupération. On fusionne avec l'existant (le nouveau lot l'emporte en cas de créneau
# identique) et on garde une fenêtre glissante de 400 créneaux (~4 jours) pour ne pas laisser le
# fichier grossir indéfiniment.
jq -n --argjson existing "${EXISTING_PRICES}" --argjson new "${NEW_PRICES}" --arg fetched_at "${FETCHED_AT}" '
  (($existing + $new) | group_by(.start) | map(last) | sort_by(.start)) as $merged
  | { fetched_at: $fetched_at, prices: $merged[-400:] }
' > data/spot-prices.json

echo "Wrote $(jq '.prices | length' data/spot-prices.json) price points to data/spot-prices.json"
