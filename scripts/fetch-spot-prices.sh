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

echo "${RESPONSE}" | jq --arg fetched_at "${FETCHED_AT}" '{
  fetched_at: $fetched_at,
  prices: [
    .france_power_exchanges[]?.values[]?
    | select(.price != null)
    | { start: .start_date, end: .end_date, price: .price }
  ] | sort_by(.start)
}' > data/spot-prices.json

echo "Wrote $(jq '.prices | length' data/spot-prices.json) price points to data/spot-prices.json"
