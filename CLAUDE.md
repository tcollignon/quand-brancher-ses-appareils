# CLAUDE.md

Ce fichier fournit des indications à Claude Code (claude.ai/code) pour travailler dans ce dépôt.

## Fins de ligne (Windows)

Si le poste de développement est sous Windows, les fichiers doivent être en fins de ligne **CRLF**. Après chaque modification d'un fichier, vérifier/convertir ses fins de ligne en CRLF avant de considérer la modification terminée.

Exception : `.gitattributes` force le **LF** pour `*.sh` et `data/*.json`, car `scripts/fetch-spot-prices.sh` s'exécute sur le runner Linux de GitHub Actions (un shebang/script en CRLF y casse) et `data/spot-prices.json` est généré par ce script. Tout le reste (y compris les workflows `.yml`) reste en CRLF.

## Texte affiché à l'utilisateur

- **Pas de tiret double** (tiret cadratin `—` ni demi-cadratin `–`) dans `index.html` : utiliser le tiret simple `-` partout, y compris dans les plages horaires (`13h00-18h30`) et les valeurs manquantes.
- **Éviter les anglicismes** dans les textes visibles (légende, tableau, panneau de détail, notes de bas de page) : préférer par exemple « marché de gros publié la veille pour le lendemain » à « day-ahead ».
- **Le panneau « Détail du calcul »** s'adresse à l'utilisateur final, pas à un développeur : décrire le calcul en phrases claires (« ce prix est comparé au prix médian... »), jamais par des noms de fonctions/fichiers/tables du code (`TIERS`, `computeMixIntensity`, `SHAPE_WEEKDAY`...), ni par des détails d'infrastructure (GitHub Actions, nom d'API RTE, etc.). Ne pas non plus faire référence à l'origine interne des seuils (l'étude ponctuelle par email qui a servi de point de départ) — c'est un détail de genèse du projet, pas une information utile à l'utilisateur.

## Projet

Une application statique, en une seule page, en français, qui indique les créneaux les moins carbonés pour lancer des appareils (lave-vaisselle, lave-linge, recharge de véhicule électrique), à partir des données en temps réel du mix électrique français.

## Développement

Aucune dépendance, aucun build, aucun gestionnaire de paquets pour la page elle-même. `index.html` est entièrement autonome (`<style>` et `<script>` inline, HTML/CSS/JS vanille). Pour travailler dessus, il suffit d'ouvrir `index.html` dans un navigateur ou de servir le dossier statiquement — rien à installer ni à compiler.

Comme le JS appelle directement une API distante depuis le navigateur (voir ci-dessous), ouvrir le fichier en `file://` fonctionne pour itérer sur la mise en page/l'UI, mais la récupération des données en direct peut se comporter différemment qu'en `http(s)://` selon la gestion CORS du navigateur. Pour vérifier un comportement dépendant des données, servir le fichier en HTTP (par ex. `python3 -m http.server`) et l'ouvrir dans un navigateur.

Il n'y a ni tests, ni linter, ni CI de build configurés dans ce dépôt. Il y a en revanche un job GitHub Actions planifié (`.github/workflows/fetch-spot-prices.yml`) qui alimente `data/spot-prices.json` — voir la section Architecture ci-dessous.

## Architecture

Tout se trouve dans `index.html`, organisé en une seule IIFE dans la balise `<script>` :

- **Récupération des données (`loadAll`)** — appelle l'API opendatasoft (`odre.opendatasoft.com`) pour le jeu de données RTE éCO2mix (`eco2mix-national-tr` pour la France, `eco2mix-regional-tr` filtré par région), en récupérant le dernier enregistrement en temps réel. Rafraîchi toutes les 5 minutes via `setInterval`.
- **Intensité carbone** — le champ `taux_co2` fourni par RTE est utilisé directement quand il est présent ; sinon `computeMixIntensity` la calcule à partir de la production par filière (en MW) pondérée par la table `FACTORS` (gCO₂/kWh par filière, par ex. nucléaire/hydraulique ≈ 6, gaz ≈ 418, charbon ≈ 1058).
- **Prévision au-delà de « maintenant »** — il n'existe pas d'API officielle de prévision d'intensité carbone chez RTE, donc les valeurs futures/des autres jours combinent deux sources dans `buildDayCurve`, chaque créneau étant exprimé comme `currentIntensity × (multiplicateur du créneau / multiplicateur de « maintenant »)` (voir `multiplierAt`) :
  - Pour les créneaux couverts par `data/spot-prices.json` (horizon day-ahead, J et J+1 une fois les prix publiés vers 13h30 CET) : le multiplicateur vient de `priceShapeAt` — le ratio (prix du créneau / prix médian du lot reçu), borné à [0.4, 2.5]. Volontairement **pas** une conversion prix → gCO2 absolue (une première version utilisait la table probabiliste de l'étude ponctuelle interne du 2026-07-17, abandonnée : elle n'est pas calibrée pour le mix français et produisait des valeurs physiquement absurdes une fois recalée sur la mesure en direct).
  - Sinon (au-delà de J+1, ou si `data/spot-prices.json` est vide/indisponible) : le multiplicateur vient de `shapeAt`, le profil journalier fixe habituel (`SHAPE_WEEKDAY` / `SHAPE_WEEKEND`).
  - Exprimer TOUJOURS chaque créneau relativement à « maintenant » (plutôt que recalculer une valeur absolue) garantit qu'un créneau dont le multiplicateur égale celui de « maintenant » affiche exactement la même valeur, quelle que soit la méthode utilisée de part et d'autre — sans cette précaution, la jointure entre créneau mesuré et créneau calculé peut sauter de façon incohérente même quand rien n'a vraiment changé.
  - Le créneau « maintenant » (`forceSlotIndex` dans `buildDayCurve`) reste toujours ancré sur la valeur mesurée en direct, jamais recalculé. Chaque créneau porte un `source` (`live` / `market` / `estimate`) utilisé pour le regroupement des lignes, ainsi qu'un `price` (ou `null`) affiché dans la colonne « Prix spot » du tableau à titre d'information seulement (voir Seuils/couleurs ci-dessous : il n'entre plus dans le classement très bon/correct/polluant/très polluant).
  - Un onglet de jour n'est affiché que si i===0 (aujourd'hui, toujours visible) ou s'il contient au moins un créneau `source==='market'` — sinon ce serait juste le profil-type générique présenté comme si c'était une vraie prévision J+2/J+3, ce que RTE ne publie jamais.
  - `data/spot-prices.json` est généré une fois par jour par le workflow `.github/workflows/fetch-spot-prices.yml` (`scripts/fetch-spot-prices.sh`), qui échange les secrets de dépôt `RTE_CLIENT_ID`/`RTE_CLIENT_SECRET` contre un token OAuth2 et appelle l'API RTE Wholesale Market (`digital.iservices.rte-france.com`) — cette API n'a pas de CORS et exige des credentials, donc impossible à appeler directement depuis le navigateur comme éCO2mix ; d'où ce job plutôt qu'un fetch direct. La page consomme le fichier généré en même-origine (`fetch('data/spot-prices.json')`), sans jamais voir les credentials.
  - Dans l'ensemble, ce n'est explicitement *pas* une vraie prévision officielle, et l'UI/le README le précisent. Le panneau repliable « Détail du calcul » (construit dans `computeDerived` sous `debug`, rendu dans `render`) expose la donnée brute reçue (relevé RTE éCO2mix, lot de prix spot) et la formule complète par créneau affiché — à tenir à jour si la méthode de calcul change, sous peine de désynchronisation entre ce qu'affiche le panneau et ce que fait réellement le code.
- **État** — un unique objet `state` (région, onglet de jour sélectionné, horloge courante, intensité en direct, répartition du mix, relevé RTE brut, prix spot) modifié uniquement via `setState(patch)`, qui fait un `Object.assign` puis appelle `render()`. C'est un pattern « re-rendu complet de la vue à chaque changement » fait sans framework — pas de diffing, pas d'arbre de composants.
- **Modèle de vue dérivé (`computeDerived`)** — fonction pure qui prend `state` et produit tout ce dont le DOM a besoin : les données du tracé SVG (ligne/aire construites à la main sous forme de chaînes de coordonnées), les bandes de fond colorées par seuil d'intensité, les lignes du tableau (regroupées en plages contiguës de même valeur arrondie ET même avis), les onglets de jour, les barres du mix, le « message du jour » (meilleur créneau à venir) et le détail de calcul (`debug`). Garder cette fonction pure/sans effet de bord — `render()` est le seul endroit qui touche au DOM.
- **Rendu (`render`)** — prend la sortie de `computeDerived()` et met à jour les nœuds/attributs du DOM de façon impérative (y compris la création d'éléments SVG bruts via l'aide `el()` utilisant `createElementNS`). Aucune librairie de templating.
- **Seuils/couleurs** — une seule table `TIERS` (4 paliers : Très bon / Correct / Polluant / Très polluant, seuils du mail du 2026-07-17 exprimés en intensité CO2e équivalente) sert de critère unique de classement, via `adviceFor(value, isDayMin)`, pour toutes les lignes quelle que soit leur `source`. Le prix spot influence la *valeur* de l'intensité affichée (voir `priceShapeAt` ci-dessus) mais ne sert plus, seul, à choisir la catégorie d'un créneau `market` : une version antérieure classait ces créneaux directement sur leur prix (table séparée `PRICE_LEVELS`/`priceAdviceFor`), ce qui pouvait afficher une intensité et une étiquette qui se contredisaient au regard de la légende (ex. « 22 gCO2/kWh » étiqueté « Polluant » alors que la légende classe 22 en « Correct »). **Ne pas réintroduire un second critère de classement** : si les seuils changent, ils doivent rester uniques dans `TIERS.maxIntensity`, appliqués au chiffre réellement affiché.
- **Régions** — le tableau `REGIONS` liste la France métropolitaine + les 12 régions continentales publiées par RTE ; `'France'` est la sélection spéciale « pays entier » qui utilise le jeu de données national plutôt que régional.

Lors de modifications, préserver la contrainte « un seul fichier HTML autonome, sans build » sauf demande explicite de l'utilisateur d'introduire de l'outillage.
