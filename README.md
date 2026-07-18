# Quand brancher ses appareils ?

Une page statique qui repère les créneaux les moins carbonés pour lancer lave-vaisselle, lave-linge ou recharge, d'après le mix électrique français en temps réel.

- Intensité carbone en direct (national ou par région), calculée à partir du mix de production RTE éCO2mix.
- Message du jour indiquant le meilleur créneau à venir.
- Graphique et tableau du jour + 3 jours suivants, par pas de 30 minutes. Les créneaux marqués € sont calculés à partir des vrais prix spot day-ahead du marché de gros ; le reste (au-delà de l'horizon day-ahead, ou si les prix sont indisponibles) est une **estimation indicative** basée sur un profil-type de journée (jour ouvré / week-end). Dans tous les cas, **ce n'est pas une prévision officielle RTE**.

## Données

- Mix de production temps réel : [RTE éCO2mix](https://www.rte-france.com/eco2mix) via l'API opendatasoft (`odre.opendatasoft.com`), interrogée directement depuis le navigateur.
- Prix spot day-ahead : API RTE Wholesale Market (`data.rte-france.com`), récupérée une fois par jour par un job planifié GitHub Actions (`.github/workflows/fetch-spot-prices.yml`) qui écrit `data/spot-prices.json` — cette API n'autorise pas les appels directs depuis un navigateur (pas de CORS, credentials OAuth2 à garder secrets), d'où le passage par un job plutôt qu'un appel direct comme pour éCO2mix. Les prix sont convertis en intensité carbone via une table probabiliste indicative (moyen de production marginal estimé par tranche de prix), voir le commentaire `PRICE_INTENSITY_TABLE` dans `index.html`.

## Développement

Aucune dépendance, aucun build pour la page elle-même : `index.html` est autonome (HTML/CSS/JS vanille). Il suffit de l'ouvrir ou de le servir statiquement. Le seul élément hors page statique est le job GitHub Actions qui alimente `data/spot-prices.json` (voir ci-dessus) ; il nécessite un compte data.rte-france.com et les secrets de dépôt `RTE_CLIENT_ID` / `RTE_CLIENT_SECRET`.
