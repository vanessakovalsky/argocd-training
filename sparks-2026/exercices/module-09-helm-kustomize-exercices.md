# Module 09 — Exercices

Fichiers fournis : `labs/m09/` (structure finale de `flotte-config` : `apps/flotte-web/{base,overlays}`, `helm/flotte-api/`, `argocd/`). Contexte CLI administrateur : `argocd context localhost:8443`.

## Lab 09.1 ⭐ — Chart Helm avec valeurs dans Git (guidé)
**Durée** : 20 min · **Objectif** : déployer `flotte-api` depuis le chart podinfo, valeurs versionnées dans `flotte-config`
**Contexte** : *Hexa Mobilité* ajoute une API à sa plateforme ; l'éditeur la fournit sous forme de chart Helm.
**Prérequis** : état final du M08

### Étapes
1. Autoriser le dépôt de charts dans le projet (s'il ne l'a pas été au M04).
   ```bash
   argocd proj add-source flotte https://stefanprodan.github.io/podinfo
   ```
2. Lire les valeurs par défaut du chart, puis copier les fichiers de valeurs fournis.
   ```bash
   helm show values podinfo --repo https://stefanprodan.github.io/podinfo --version 6.17.0 | head -25
   cd <FLOTTE_CONFIG>
   mkdir -p helm/flotte-api
   cp <FORMATION>/labs/m09/helm/flotte-api/*.yaml helm/flotte-api/
   cat helm/flotte-api/values-common.yaml helm/flotte-api/values-dev.yaml
   ```
3. Tester le rendu en local avant tout commit.
   ```bash
   helm template flotte-api podinfo --repo https://stefanprodan.github.io/podinfo --version 6.17.0 \
     -f helm/flotte-api/values-common.yaml -f helm/flotte-api/values-dev.yaml | grep -E 'replicas:|UI_'
   ```
   Résultat attendu :
   ```
     replicas: 1
           - name: PODINFO_UI_MESSAGE
           - name: PODINFO_UI_COLOR
   ```
4. Ajouter l'Application multi-sources, committer, pousser, créer.
   ```bash
   sed "s|<GITLAB_USER>|$GITLAB_USER|" <FORMATION>/labs/m09/argocd/flotte-api-dev.yaml > argocd/flotte-api-dev.yaml
   git add helm/ argocd/ && git commit -m "feat: flotte-api (chart Helm)" && git push
   kubectl apply -f argocd/flotte-api-dev.yaml
   argocd app wait flotte-api-dev --sync --health
   argocd app get flotte-api-dev | grep -E 'Repo|Helm Values|Sync Status|Health Status'
   ```
   Résultat attendu : deux sources (dépôt de charts, `flotte-config` avec `Ref: values`), `Synced to 6.17.0`, `Healthy`.
5. Vérifier le rendu par ArgoCD et l'absence de release Helm.
   ```bash
   argocd app manifests flotte-api-dev | grep -E 'UI_MESSAGE|UI_COLOR' -A1
   helm list -n flotte-dev
   ```
   Résultat attendu : `Hexa Mobilite - API`, `'#2e7d32'` ; `helm list` vide.

### Critères de réussite
- [ ] `flotte-api-dev` `Synced` / `Healthy`, Deployment `flotte-api-podinfo` à 1 réplica
- [ ] Valeurs lues depuis `flotte-config` (modifier `values-dev.yaml` change le rendu)

---

## Exercice 09.2 ⭐⭐ — Priorité des valeurs Helm (semi-autonome)
**Durée** : 10 min · **Objectif** : vérifier l'ordre de priorité des valeurs dans ArgoCD
**Contexte** : un incident exige 2 réplicas de l'API immédiatement, sans attendre une merge request.

**Énoncé** :
- Surcharger temporairement `replicaCount` à 2 par la CLI ArgoCD ; observer le rendu, la synchronisation et ce que montre Git.
- Ajouter en plus `valuesObject: {replicaCount: 3}` dans l'Application (fichier), et prédire le résultat avant de vérifier.
- Revenir à l'état versionné (une seule source de vérité) et expliquer le risque d'une surcharge non tracée.

**Indices** : `argocd app set flotte-api-dev --source-position 1 --helm-set replicaCount=2` ; `argocd app unset` ; `argocd app manifests | grep replicas`.

**Critères de réussite** :
- [ ] Ordre vérifié : `parameters` (2) l'emporte sur `valuesObject` (3) et `valueFiles` (1)
- [ ] Application revenue à 1 réplica, sans `parameters` ni `valuesObject`
- [ ] Risque expliqué (self-heal, réapplication du fichier, absence de trace)

---

## Lab 09.3 ⭐⭐ — `flotte-web` en base et overlays Kustomize (guidé)
**Durée** : 25 min · **Objectif** : remplacer les copies `dev` / `recette` par une base et des overlays
**Contexte** : `apps/flotte-web/` et `apps/flotte-web-recette/` divergent déjà ; l'équipe veut décrire `flotte-web` une seule fois.
**Prérequis** : Lab 08.2 (Rollout), Exercice 08.4 (recette) ou rattrapage M08

### Étapes
1. Remplacer les fichiers à plat par la structure fournie.
   ```bash
   cd <FLOTTE_CONFIG>
   git rm -q apps/flotte-web/*.yaml
   git rm -rq apps/flotte-web-recette
   cp -r <FORMATION>/labs/m09/apps/flotte-web/base <FORMATION>/labs/m09/apps/flotte-web/overlays apps/flotte-web/
   find apps/flotte-web -type f | sort
   ```
2. Lire `base/kustomization.yaml`, puis chaque overlay ; repérer : générateur de ConfigMap, `images`, `replicas`, patch de la recette, `configurations`.
3. Vérifier le rendu des trois environnements.
   ```bash
   for e in dev recette prod; do
     echo "== $e"; kubectl kustomize apps/flotte-web/overlays/$e \
       | grep -E 'image: ghcr|replicas:|blueGreen|canary:|config-'
   done
   ```
   Résultat attendu : `dev` en `6.17.0`, canari ; `recette` en `6.16.0`, `blueGreen`, 2 réplicas ; `prod` en `6.16.0`, canari, 4 réplicas ; une ConfigMap au nom haché différent par environnement.
4. Pointer les Applications sur les overlays, committer, pousser, appliquer.
   ```bash
   sed -i 's#path: apps/flotte-web$#path: apps/flotte-web/overlays/dev#' argocd/flotte-web-dev.yaml
   sed -i 's#path: apps/flotte-web-recette$#path: apps/flotte-web/overlays/recette#' argocd/flotte-web-recette.yaml
   git add -A && git commit -m "refactor: Kustomize base + overlays" && git push
   kubectl apply -f argocd/flotte-web-dev.yaml -f argocd/flotte-web-recette.yaml
   ```
5. Suivre les livraisons (canari en dev, bleu-vert en recette) et promouvoir ; vérifier le message servi en dev.
   ```bash
   kubectl argo rollouts promote flotte-web -n flotte-dev --full
   kubectl argo rollouts promote flotte-web -n flotte-recette --full
   argocd app wait flotte-web-dev flotte-web-recette --health
   kubectl port-forward -n flotte-dev svc/flotte-web 9898:80 &
   curl -s localhost:9898 | grep -E '"(version|message)"'
   ```
   Résultat attendu : `"version": "6.17.0"`, `"message": "Hexa Mobilite - DEV"`.

### Critères de réussite
- [ ] Plus aucun fichier à plat dans `apps/flotte-web/`, plus de dossier `apps/flotte-web-recette/`
- [ ] Deux Applications `Synced` / `Healthy` sur leurs overlays
- [ ] Message propre à chaque environnement

---

## Exercice 09.4 ⭐⭐ — Changer la configuration sans oublier les pods (semi-autonome)
**Durée** : 10 min · **Objectif** : vérifier qu'une modification de configuration atteint réellement les pods
**Contexte** : le bonus du M06 a montré qu'une ConfigMap modifiée seule ne redémarre pas les pods.

**Énoncé** :
- Modifier le message de `dev` dans son overlay ; pousser ; suivre la livraison.
- Relever les ConfigMaps du namespace avant et après, et l'état affiché par ArgoCD pour l'ancienne.
- Vérifier le message servi par l'application.
- Expliquer le rôle des trois annotations du générateur dans la base.

**Critères de réussite** :
- [ ] Nouvelle ConfigMap (nom haché différent) et nouveaux pods
- [ ] Ancienne ConfigMap conservée, affichée `ignored (no prune)`, application `Synced`
- [ ] Rôle de `sync-wave`, `Prune=false`, `IgnoreExtraneous` expliqué

---

## Défi 09.5 ⭐⭐⭐ — Environnement de production (autonome)
**Durée** : 15 min (en autonomie si le temps manque) · **Objectif** : ajouter la production avec une politique de livraison adaptée
**Contexte** : la production d'*Hexa Mobilité* doit suivre un tag Git de release et ne jamais se synchroniser seule.

**Énoncé** :
- Créer `argocd/flotte-web-prod.yaml` : overlay `prod`, namespace `flotte-prod`, synchronisation MANUELLE, `targetRevision` = tag Git `v1.0.0`.
- Créer le tag `v1.0.0` sur le commit courant, le pousser, créer et synchroniser l'Application.
- Livrer une modification sur `main` : constater que `prod` ne bouge pas ; publier `v1.1.0` et déplacer la production vers ce tag par un commit.
- Comparer en une phrase ce mode de promotion avec celui de `dev`.

**Critères de réussite** :
- [ ] `flotte-web-prod` `Synced to v1.0.0`, 4 réplicas, message `Hexa Mobilite`
- [ ] Commit sur `main` sans effet sur `prod`
- [ ] Promotion `v1.0.0` → `v1.1.0` par un commit de l'Application

---

## Bonus 🚀
Activer `kustomize.buildOptions: --enable-helm` dans `argocd-cm` et décrire, dans un overlay de test, le chart podinfo via `helmCharts` (Kustomize). Comparer avec l'Application multi-sources du Lab 09.1 : lisibilité, emplacement des valeurs, effet global du réglage.
