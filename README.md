# Quand brancher ses appareils ?

Une page statique qui repère les créneaux les moins carbonés pour lancer lave-vaisselle, lave-linge ou recharge, d'après le mix électrique français en temps réel.

- Intensité carbone en direct (national ou par région), calculée à partir du mix de production RTE éCO2mix.
- Message du jour indiquant le meilleur créneau à venir.
- Graphique et tableau du jour + 3 jours suivants, par pas de 30 minutes. Les prévisions au-delà du temps réel sont une **estimation indicative** basée sur un profil-type de journée (jour ouvré / week-end), pas une prévision officielle RTE.

## Données

Source : [RTE éCO2mix](https://www.rte-france.com/eco2mix) via l'API opendatasoft (`odre.opendatasoft.com`), interrogée directement depuis le navigateur.

## Développement

Aucune dépendance, aucun build : `index.html` est autonome (HTML/CSS/JS vanille). Il suffit de l'ouvrir ou de le servir statiquement.
