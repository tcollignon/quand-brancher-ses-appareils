# CLAUDE.md

Ce fichier fournit des indications à Claude Code (claude.ai/code) pour travailler dans ce dépôt.

## Fins de ligne (Windows)

Si le poste de développement est sous Windows, les fichiers doivent être en fins de ligne **CRLF**. Après chaque modification d'un fichier, vérifier/convertir ses fins de ligne en CRLF avant de considérer la modification terminée.

Exception : `.gitattributes` force le **LF** pour `*.sh` et `data/*.json`, car `scripts/fetch-spot-prices.sh` s'exécute sur le runner Linux de GitHub Actions (un shebang/script en CRLF y casse) et `data/spot-prices.json` est généré par ce script. Tout le reste (y compris les workflows `.yml`) reste en CRLF.

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
- **Prévision au-delà de « maintenant »** — il n'existe pas d'API officielle de prévision d'intensité carbone chez RTE, donc les valeurs futures/des autres jours combinent deux sources dans `buildDayCurve` :
  - Pour les créneaux couverts par `data/spot-prices.json` (horizon day-ahead, J et J+1 une fois les prix publiés vers 13h30 CET) : le prix spot réel du créneau est converti en intensité via `intensityFromPrice` / `PRICE_INTENSITY_TABLE`, une table probabiliste (prix → proba du moyen de production marginal → intensité pondérée) issue d'une étude ponctuelle interne, pas d'une source officielle — à recaler si les coûts de combustible (notamment le gaz) évoluent significativement.
  - Sinon (au-delà de J+1, ou si `data/spot-prices.json` est vide/indisponible) : profil journalier fixe (`SHAPE_WEEKDAY` / `SHAPE_WEEKEND`, des points heure → multiplicateur d'intensité relative) recalé sur le `referenceLevel` mesuré actuellement.
  - Le créneau « maintenant » (`forceSlotIndex` dans `buildDayCurve`) reste toujours ancré sur la valeur mesurée en direct, jamais sur le prix spot, pour préserver l'invariant existant. Chaque créneau porte un `source` (`live` / `market` / `estimate`) utilisé pour l'affichage (badge `€` dans le tableau) et pour le regroupement des lignes.
  - `data/spot-prices.json` est généré une fois par jour par le workflow `.github/workflows/fetch-spot-prices.yml` (`scripts/fetch-spot-prices.sh`), qui échange les secrets de dépôt `RTE_CLIENT_ID`/`RTE_CLIENT_SECRET` contre un token OAuth2 et appelle l'API RTE Wholesale Market (`digital.iservices.rte-france.com`) — cette API n'a pas de CORS et exige des credentials, donc impossible à appeler directement depuis le navigateur comme éCO2mix ; d'où ce job plutôt qu'un fetch direct. La page consomme le fichier généré en même-origine (`fetch('data/spot-prices.json')`), sans jamais voir les credentials.
  - Dans l'ensemble, ce n'est explicitement *pas* une vraie prévision officielle, et l'UI/le README le précisent.
- **État** — un unique objet `state` (région, onglet de jour sélectionné, horloge courante, intensité en direct, répartition du mix) modifié uniquement via `setState(patch)`, qui fait un `Object.assign` puis appelle `render()`. C'est un pattern « re-rendu complet de la vue à chaque changement » fait sans framework — pas de diffing, pas d'arbre de composants.
- **Modèle de vue dérivé (`computeDerived`)** — fonction pure qui prend `state` et produit tout ce dont le DOM a besoin : les données du tracé SVG (ligne/aire construites à la main sous forme de chaînes de coordonnées), les bandes de fond colorées par seuil d'intensité, les lignes du tableau (regroupées en plages contiguës de même valeur arrondie), les onglets de jour, les barres du mix, et le « message du jour » (meilleur créneau à venir). Garder cette fonction pure/sans effet de bord — `render()` est le seul endroit qui touche au DOM.
- **Rendu (`render`)** — prend la sortie de `computeDerived()` et met à jour les nœuds/attributs du DOM de façon impérative (y compris la création d'éléments SVG bruts via l'aide `el()` utilisant `createElementNS`). Aucune librairie de templating.
- **Seuils/couleurs** — les bandes d'intensité (≤35 « très bon » … >80 « fortement à éviter ») et leurs couleurs sont définies via `adviceFor` et le tableau `bandDefs` dans `computeDerived` ; garder ces deux éléments synchronisés si les seuils changent, car ils sont actuellement dupliqués (l'un pilote le texte du tableau/message, l'autre les bandes de fond du graphique).
- **Régions** — le tableau `REGIONS` liste la France métropolitaine + les 12 régions continentales publiées par RTE ; `'France'` est la sélection spéciale « pays entier » qui utilise le jeu de données national plutôt que régional.

Lors de modifications, préserver la contrainte « un seul fichier HTML autonome, sans build » sauf demande explicite de l'utilisateur d'introduire de l'outillage.
