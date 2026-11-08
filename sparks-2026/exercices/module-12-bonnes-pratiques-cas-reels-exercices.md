# Module 12 — Exercices

Fichiers fournis : `labs/m12/applicationset-flotte-web.yaml`. Contexte CLI administrateur : `argocd context localhost:8443`.

## Lab 12.1 ⭐⭐ — Générer les environnements avec un ApplicationSet (guidé)
**Durée** : 15 min · **Objectif** : remplacer les Applications écrites à la main par un générateur
**Contexte** : *Hexa Mobilité* prévoit un environnement par client de démonstration ; écrire une Application à chaque fois ne tient plus.
**Prérequis** : état final du M11 (overlays `dev`, `recette`, `prod`)

### Étapes
1. Copier l'ApplicationSet, renseigner l'URL du dépôt, le lire (générateur, exclusion de `prod`, modèle), committer, appliquer.
   ```bash
   cd <FLOTTE_CONFIG>
   sed "s|<GITLAB_USER>|$GITLAB_USER|g" <FORMATION>/labs/m12/applicationset-flotte-web.yaml \
     > argocd/applicationset-flotte-web.yaml
   git add argocd/ && git commit -m "feat: ApplicationSet flotte-web" && git push
   kubectl apply -f argocd/applicationset-flotte-web.yaml
   ```
2. Vérifier la génération et l'adoption des Applications existantes.
   ```bash
   kubectl get applicationset flotte-web -n argocd \
     -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
   kubectl get app flotte-web-dev -n argocd -o jsonpath='{.metadata.ownerReferences[0].kind}{"\n"}'
   ```
   Résultat attendu :
   ```
   ErrorOccurred=False
   ParametersGenerated=True
   ResourcesUpToDate=True
   ApplicationSet
   ```
3. Ajouter un environnement `demo` : créer `apps/flotte-web/overlays/demo/kustomization.yaml` (base, 1 réplica, message `Hexa Mobilite - DEMO`), committer, pousser, puis demander un rafraîchissement du générateur.
   ```bash
   kubectl annotate applicationset flotte-web -n argocd \
     argocd.argoproj.io/application-set-refresh=true --overwrite
   argocd app list | grep flotte-web
   ```
   Résultat attendu : `argocd/flotte-web-demo  flotte-demo  Synced  Healthy` en plus de `dev` et `recette`.
4. Supprimer le dossier `demo`, pousser, rafraîchir : observer la disparition de l'Application et de ses ressources.

### Critères de réussite
- [ ] `flotte-web-dev` et `flotte-web-recette` possédées par l'ApplicationSet
- [ ] Environnement `demo` créé par un simple dossier, puis supprimé
- [ ] `prod` non générée (exclusion)

---

## Exercice 12.2 ⭐ — Sauvegarder la configuration d'ArgoCD (guidé)
**Durée** : 5 min · **Objectif** : produire et évaluer une sauvegarde
**Contexte** : la procédure de reprise d'activité d'*Hexa Mobilité* exige une sauvegarde quotidienne.

**Énoncé** :
```bash
argocd admin export -n argocd > argocd-backup.yaml
grep -E '^kind:' argocd-backup.yaml | sort | uniq -c
grep -c 'kind: Secret' argocd-backup.yaml
```
- Relever les types d'objets sauvegardés.
- Indiquer ce que la sauvegarde ne contient PAS et qui est pourtant nécessaire à une reprise.
- Proposer un lieu de stockage et une fréquence.

**Critères de réussite** :
- [ ] Types d'objets relevés (Applications, ApplicationSet, AppProjects, ConfigMaps, Secrets)
- [ ] Éléments manquants identifiés (dépôts Git, clé de Sealed Secrets, contrôleurs installés à part, ressources déployées)
- [ ] Stockage chiffré hors Git proposé

---

## Exercice 12.3 ⭐⭐ — Plan de mise à niveau (semi-autonome)
**Durée** : 5 min · **Objectif** : préparer une montée de version sans surprise
**Contexte** : une autre filiale d'*Hexa Mobilité* exploite encore ArgoCD 3.4.

**Énoncé** : rédiger les étapes de passage de 3.4 à 3.6 (ordre, documents à lire, tests, retour arrière possible), en s'appuyant sur la page *Upgrading* de la documentation.

**Critères de réussite** :
- [ ] Deux sauts successifs (3.4 → 3.5 → 3.6), notes `3.4-3.5` et `3.5-3.6` lues
- [ ] Sauvegarde avant chaque saut, essai sur un cluster de recette
- [ ] Vérifications après mise à niveau (pods, applications `Synced`, connexion SSO)

---

## Étude de cas 12.4 ⭐⭐ — *Transports Régionaux Sud* (binôme)
**Durée** : 25 min (20 min d'analyse + 5 min de restitution) · **Objectif** : appliquer les bonnes pratiques à une situation d'entreprise
**Contexte** (entreprise fictive) :
- 12 équipes produit, 140 microservices, 3 clusters de production (2 régions + secours), 1 cluster de recette par région.
- Livraisons : jusqu'à 30 par jour en recette ; en production, uniquement le mardi et le jeudi de 7 h à 9 h, après validation du responsable de la plateforme.
- Annuaire d'entreprise (OIDC) ; coffre de secrets déjà en place.
- Un incident récent : un correctif manuel en production, écrasé au déploiement suivant.
- Le cluster de secours n'est pas joignable depuis le réseau d'administration principal.

**Énoncé** : à l'aide de la grille d'analyse (S12.2), proposer :
- l'organisation des dépôts et des AppProjects ;
- la gestion des identités et des droits ;
- la stratégie de génération des Applications (ApplicationSet, générateurs) ;
- la politique de livraison (synchronisation, fenêtres, canari ou bleu-vert) ;
- la gestion des secrets ;
- la réponse à l'incident cité et au cluster de secours ;
- un schéma de l'architecture cible.

**Critères de réussite** :
- [ ] Chaque contrainte du contexte reliée à une pratique du cours
- [ ] Schéma lisible (dépôts, ArgoCD, clusters, flux)
- [ ] Restitution en 5 minutes

---

## Défi 12.5 ⭐⭐⭐ — Application racine (App of Apps) (autonome)
**Durée** : 10 min (en autonomie) · **Objectif** : reconstruire toute la plateforme à partir d'une seule Application
**Contexte** : après une perte du cluster, l'équipe veut tout recréer en deux commandes.

**Énoncé** :
- Créer une Application `hexa-racine` (projet `default`) qui déploie le dossier `argocd/` de `flotte-config` dans le namespace `argocd`, en excluant les fichiers des Applications désormais générées par l'ApplicationSet.
- Synchroniser ; relever ce qui est créé, adopté ou ignoré.
- Supprimer la racine SANS supprimer les Applications enfants, puis expliquer le rôle du finalizer.

**Critères de réussite** :
- [ ] Racine `Synced` : ApplicationSet, `flotte-api-dev` et `flotte-web-prod` gérés
- [ ] `flotte-web-prod` créée mais non synchronisée (politique manuelle respectée)
- [ ] Suppression non cascadée : Applications enfants toujours présentes

---

## Bonus 🚀
Lire la page *Source Hydrator* de la documentation (fonctionnalité bêta depuis 3.5) et expliquer en trois lignes ce qu'elle changerait pour la relecture des merge requests de `flotte-config`.
