# CLAUDE.md

Ce fichier fournit des indications à Claude Code (claude.ai/code) pour travailler dans ce dépôt.

## Fins de ligne (Windows)

Si le poste de développement est sous Windows, les fichiers doivent être en fins de ligne **CRLF**. Après chaque modification d'un fichier, vérifier/convertir ses fins de ligne en CRLF avant de considérer la modification terminée.

## Projet

Une application statique, en une seule page, en français, qui indique les créneaux les moins carbonés pour lancer des appareils (lave-vaisselle, lave-linge, recharge de véhicule électrique), à partir des données en temps réel du mix électrique français.

## Développement

Aucune dépendance, aucun build, aucun gestionnaire de paquets. `index.html` est entièrement autonome (`<style>` et `<script>` inline, HTML/CSS/JS vanille). Pour travailler dessus, il suffit d'ouvrir `index.html` dans un navigateur ou de servir le dossier statiquement — rien à installer ni à compiler.

Comme le JS appelle directement une API distante depuis le navigateur (voir ci-dessous), ouvrir le fichier en `file://` fonctionne pour itérer sur la mise en page/l'UI, mais la récupération des données en direct peut se comporter différemment qu'en `http(s)://` selon la gestion CORS du navigateur. Pour vérifier un comportement dépendant des données, servir le fichier en HTTP (par ex. `python3 -m http.server`) et l'ouvrir dans un navigateur.

Il n'y a ni tests, ni linter, ni CI configurés dans ce dépôt.

## Architecture

Tout se trouve dans `index.html`, organisé en une seule IIFE dans la balise `<script>` :

- **Récupération des données (`loadAll`)** — appelle l'API opendatasoft (`odre.opendatasoft.com`) pour le jeu de données RTE éCO2mix (`eco2mix-national-tr` pour la France, `eco2mix-regional-tr` filtré par région), en récupérant le dernier enregistrement en temps réel. Rafraîchi toutes les 5 minutes via `setInterval`.
- **Intensité carbone** — le champ `taux_co2` fourni par RTE est utilisé directement quand il est présent ; sinon `computeMixIntensity` la calcule à partir de la production par filière (en MW) pondérée par la table `FACTORS` (gCO₂/kWh par filière, par ex. nucléaire/hydraulique ≈ 6, gaz ≈ 418, charbon ≈ 1058).
- **Prévision au-delà de « maintenant »** — il n'existe pas d'API officielle de prévision d'intensité carbone chez RTE, donc les valeurs futures/des autres jours sont une **estimation** : `buildDayCurve` recale un profil journalier fixe (`SHAPE_WEEKDAY` / `SHAPE_WEEKEND`, des points heure → multiplicateur d'intensité relative) sur le `referenceLevel` mesuré actuellement, de sorte que la courbe estimée pour « maintenant » corresponde toujours à la valeur mesurée en direct. Ce n'est explicitement *pas* une vraie prévision, et l'UI/le README le précisent.
- **État** — un unique objet `state` (région, onglet de jour sélectionné, horloge courante, intensité en direct, répartition du mix) modifié uniquement via `setState(patch)`, qui fait un `Object.assign` puis appelle `render()`. C'est un pattern « re-rendu complet de la vue à chaque changement » fait sans framework — pas de diffing, pas d'arbre de composants.
- **Modèle de vue dérivé (`computeDerived`)** — fonction pure qui prend `state` et produit tout ce dont le DOM a besoin : les données du tracé SVG (ligne/aire construites à la main sous forme de chaînes de coordonnées), les bandes de fond colorées par seuil d'intensité, les lignes du tableau (regroupées en plages contiguës de même valeur arrondie), les onglets de jour, les barres du mix, et le « message du jour » (meilleur créneau à venir). Garder cette fonction pure/sans effet de bord — `render()` est le seul endroit qui touche au DOM.
- **Rendu (`render`)** — prend la sortie de `computeDerived()` et met à jour les nœuds/attributs du DOM de façon impérative (y compris la création d'éléments SVG bruts via l'aide `el()` utilisant `createElementNS`). Aucune librairie de templating.
- **Seuils/couleurs** — les bandes d'intensité (≤35 « très bon » … >80 « fortement à éviter ») et leurs couleurs sont définies via `adviceFor` et le tableau `bandDefs` dans `computeDerived` ; garder ces deux éléments synchronisés si les seuils changent, car ils sont actuellement dupliqués (l'un pilote le texte du tableau/message, l'autre les bandes de fond du graphique).
- **Régions** — le tableau `REGIONS` liste la France métropolitaine + les 12 régions continentales publiées par RTE ; `'France'` est la sélection spéciale « pays entier » qui utilise le jeu de données national plutôt que régional.

Lors de modifications, préserver la contrainte « un seul fichier HTML autonome, sans build » sauf demande explicite de l'utilisateur d'introduire de l'outillage.
