# Module 08 — Exercices

Fichiers fournis : `labs/m08/` (Rollout canari, recette bleu-vert, analyse). Contexte CLI administrateur : `argocd context localhost:8443`.

## Lab 08.1 ⭐ — Installer Argo Rollouts (guidé)
**Durée** : 10 min · **Objectif** : disposer du contrôleur Argo Rollouts v1.10.2 et du plugin `kubectl`
**Contexte** : l'équipe ops d'*Hexa Mobilité* ajoute les stratégies de livraison progressive à la plateforme.
**Prérequis** : état final du M07

### Étapes
1. Installer le contrôleur.
   ```bash
   kubectl create namespace argo-rollouts
   kubectl apply -n argo-rollouts --server-side --force-conflicts \
     -f https://github.com/argoproj/argo-rollouts/releases/download/v1.10.2/install.yaml
   kubectl rollout status deploy/argo-rollouts -n argo-rollouts
   kubectl get crd | grep -E 'rollouts|analysis|experiments'
   ```
   Résultat attendu : `deployment "argo-rollouts" successfully rolled out`, puis 5 CRD (`analysisruns`, `analysistemplates`, `clusteranalysistemplates`, `experiments`, `rollouts`).
2. Installer le plugin (si absent du poste) et vérifier sa version.
   ```bash
   V=v1.10.2
   curl -sSLO https://github.com/argoproj/argo-rollouts/releases/download/$V/kubectl-argo-rollouts-linux-amd64
   curl -sSLO https://github.com/argoproj/argo-rollouts/releases/download/$V/argo-rollouts-checksums.txt
   grep kubectl-argo-rollouts-linux-amd64 argo-rollouts-checksums.txt | sha256sum -c
   sudo install -m 555 kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
   kubectl argo rollouts version
   ```
   Résultat attendu : `kubectl-argo-rollouts-linux-amd64: OK`, puis `kubectl-argo-rollouts: v1.10.2+be8a622`.

### Critères de réussite
- [ ] Pod `argo-rollouts` `Running`, 5 CRD présentes
- [ ] `kubectl argo rollouts version` affiche `v1.10.2`

---

## Lab 08.2 ⭐ — Livraison canari pilotée depuis ArgoCD (guidé)
**Durée** : 20 min · **Objectif** : livrer `6.17.0` à 25 %, puis 50 %, puis 100 % de `flotte-web`
**Contexte** : la nouvelle version de `flotte-web` est exposée d'abord à une partie des pods.
**Prérequis** : Lab 08.1

### Étapes
1. Remplacer le Deployment par le Rollout fourni, committer, pousser.
   ```bash
   cd <FLOTTE_CONFIG>
   git rm apps/flotte-web/deployment.yaml
   cp <FORMATION>/labs/m08/rollout-canary.yaml apps/flotte-web/rollout.yaml
   git add apps/ && git commit -m "feat: flotte-web en Rollout canari" && git push
   argocd app get flotte-web-dev --refresh > /dev/null && argocd app wait flotte-web-dev --sync --health
   argocd app get flotte-web-dev | grep -E 'Deployment|Rollout'
   ```
   Résultat attendu :
   ```
   apps         Deployment  flotte-dev  flotte-web           Succeeded  Pruned             pruned
   argoproj.io  Rollout     flotte-dev  flotte-web           Synced     Healthy            rollout.argoproj.io/flotte-web created
   ```
2. Livrer `6.17.0` et suivre le Rollout (second terminal, `Ctrl+C` pour quitter).
   ```bash
   sed -i -E 's#(podinfo:)[0-9.]+#\16.17.0#' apps/flotte-web/rollout.yaml
   git commit -am "feat: flotte-web 6.17.0 (canari)" && git push
   argocd app get flotte-web-dev --refresh > /dev/null
   kubectl argo rollouts get rollout flotte-web -n flotte-dev --watch
   ```
   Résultat attendu : étape 1/5 (25 %, 1 pod `canary`), pause de 30 s, étape 3/5 (50 %), puis `Paused` / `CanaryPauseStep`.
3. Observer l'état côté ArgoCD et lister les actions disponibles.
   ```bash
   argocd app get flotte-web-dev | grep -E 'Health Status|Rollout'
   argocd app actions list flotte-web-dev --kind Rollout
   ```
   Résultat attendu : `Health Status: Suspended` ; actions `resume`, `promote-full`, `abort`, `pause`, `restart`, `skip-current-step`.
4. Promouvoir depuis ArgoCD (UI : menu de la ressource Rollout → *Resume*, ou CLI).
   ```bash
   argocd app actions run flotte-web-dev resume --kind Rollout --resource-name flotte-web
   argocd app wait flotte-web-dev --health
   kubectl argo rollouts get rollout flotte-web -n flotte-dev | grep -E 'Status|Images'
   ```
   Résultat attendu : `✔ Healthy`, image `6.17.0 (stable)` ; smoke test PostSync `Succeeded`.

### Critères de réussite
- [ ] Étapes 25 % → 50 % → 100 % observées
- [ ] Application `Suspended` pendant la pause, `Healthy` après promotion
- [ ] Smoke test exécuté après la promotion complète

---

## Exercice 08.3 ⭐⭐ — Interrompre un canari défaillant (semi-autonome)
**Durée** : 10 min · **Objectif** : protéger les utilisateurs d'une version en échec
**Contexte** : la version `6.99.0` (inexistante) est livrée par erreur.

**Énoncé** :
- Livrer `6.99.0` par Git ; observer le Rollout et l'application (santé, message) après l'échéance de progression.
- Interrompre la livraison par une action ArgoCD ; vérifier que les 4 pods servent toujours la version stable.
- Revenir à un état sain par Git ; expliquer pourquoi l'application reste `Degraded` tant que Git n'est pas corrigé.
- Vérifier, connecté en `dev-alice`, si l'action `resume` est autorisée, et proposer la règle RBAC qui l'autoriserait.

**Indices** : `argocd app actions run <APP> abort --kind Rollout --resource-name flotte-web` ; `argocd app terminate-op` avant le revert.

**Critères de réussite** :
- [ ] Message `ProgressDeadlineExceeded` relevé, puis `RolloutAborted`
- [ ] Version stable servie pendant tout l'incident
- [ ] Retour `Healthy` après `git revert` ; règle RBAC proposée

---

## Exercice 08.4 ⭐⭐ — Bleu-vert en recette (semi-autonome)
**Durée** : 15 min · **Objectif** : tester une version sur un service de prévisualisation avant de basculer le trafic
**Contexte** : en recette, l'équipe métier valide chaque version avant qu'elle ne remplace la précédente.

**Énoncé** :
- Ajouter à `flotte-config` le dossier `apps/flotte-web-recette/` (fichiers de `labs/m08/flotte-web-recette/`) et l'Application `argocd/flotte-web-recette.yaml` (modèle `labs/m08/flotte-web-recette-app.yaml`) ; créer l'Application.
- Livrer `6.17.0` en recette ; pendant la pause, interroger les deux services et relever la version servie par chacun.
- Promouvoir (ArgoCD ou plugin) et vérifier la version servie par le service actif.

**Indices** : `kubectl port-forward -n flotte-recette svc/flotte-web 9901:80` et `svc/flotte-web-preview 9902:80` ; `curl -s localhost:9901 | grep version`.

**Critères de réussite** :
- [ ] Pendant la pause : service actif = ancienne version, preview = `6.17.0`
- [ ] Après promotion : service actif = `6.17.0`
- [ ] Sélecteurs des services observés (`rollouts-pod-template-hash`)

---

## Défi 08.5 ⭐⭐⭐ — Analyse automatique du canari (autonome)
**Durée** : 5 min en séance (suite en autonomie) · **Objectif** : confier la décision de promotion à une mesure
**Contexte** : l'équipe veut que le canari s'interrompe seul si la nouvelle version ne répond pas.

**Énoncé** :
- Ajouter `labs/m08/analysis-template.yaml` et `labs/m08/service-canary.yaml` dans `apps/flotte-web/` ; déclarer le service canari et remplacer la pause de 30 s par une étape d'analyse `flotte-smoke`.
- Livrer une version et vérifier que l'`AnalysisRun` réussit et que le canari continue.
- Simuler une version défaillante (analyse pointée vers `/status/500`, point de terminaison de podinfo qui renvoie une erreur 500) et constater l'interruption automatique.
- Rétablir l'état sain.

**Critères de réussite** :
- [ ] `kubectl get analysisrun -n flotte-dev` : une analyse `Successful`, une `Failed`
- [ ] Message `RolloutAborted ... Metric "readyz" assessed Failed`
- [ ] État final `Healthy`

---

## Défi 08.6 ⭐⭐⭐ — Migrer un Deployment existant vers un Rollout sans coupure (autonome)
**Durée** : 25 min · **Objectif** : adopter Argo Rollouts sur une application en production sans recréer ses pods ni interrompre le service
**Contexte** : d'autres applications d'*Hexa Mobilité* tournent en Deployment classique ; supprimer le Deployment pour le remplacer par un Rollout provoquerait une coupure.

**Énoncé** :
- Application `flotte-web-mig` (namespace `flotte-mig`, synchronisation automatique **avec self-heal**) : Deployment `flotte-web` (3 réplicas, `podinfo:6.16.0`) et Service, issus d'un dossier `apps/flotte-web-mig/` de `flotte-config`.
- Lancer dans `flotte-mig` une sonde qui interroge le Service chaque seconde et journalise `OK` / `KO`.
- Ajouter un Rollout qui **référence** le Deployment existant (sans recopier le gabarit de pod), réduction progressive de l'ancien.
- Observer pendant 2 minutes : réplicas du Deployment, statut de l'Application, opérations de synchronisation. Expliquer le conflit, puis le résoudre dans Git.
- Compter les `KO` de la sonde. Nettoyer.

**Indices** : champ `spec.workloadRef` du Rollout (`apiVersion`, `kind`, `name`, `scaleDown`) ; `argocd app diff` ; `.status.operationState.finishedAt`.

**Critères de réussite** :
- [ ] Rollout `Healthy` à 3 réplicas, Deployment à `0/0`
- [ ] Conflit self-heal / Rollouts identifié (différence `replicas: 0` / `replicas: 3`) puis résolu : `Synced` / `Healthy`
- [ ] Sonde : 0 `KO` pendant toute la migration

---

## Défi 08.7 ⭐⭐⭐ — Bleu-vert : analyse de la preview avant bascule (autonome)
**Durée** : 20 min · **Objectif** : automatiser la validation de recette : bascule automatique si la preview répond, aucune bascule sinon
**Contexte** : en recette (exercice 08.4), la promotion est manuelle. L'équipe veut une promotion automatique 20 s après une vérification réussie de la preview, et aucun trafic vers une version qui échoue.

**Énoncé** :
- `AnalysisTemplate` `flotte-preview-check` : 3 appels HTTP (toutes les 5 s, aucun échec toléré) vers le service preview, chemin passé en **argument** (`/readyz` par défaut).
- Rollout de recette : analyse avant promotion, promotion automatique au bout de 20 s.
- Livrer `6.17.0` : relever la chronologie (analyse, pause, bascule) et le hash du service actif à chaque étape.
- Livrer `6.15.0` avec l'argument `/status/500` : relever le message, le service actif, la santé de l'Application.
- Revenir à l'état sain par Git uniquement.

**Indices** : `strategy.blueGreen.prePromotionAnalysis` (`templates`, `args`) ; `autoPromotionSeconds` ; `{{args.<NOM>}}` dans le gabarit ; `kubectl get analysisrun -n flotte-recette`.

**Critères de réussite** :
- [ ] `6.17.0` : `AnalysisRun` `Successful`, puis `BlueGreenPause`, puis bascule automatique du service actif
- [ ] `6.15.0` : `RolloutAborted ... pre-promotion analysis ... Metric "preview" assessed Failed`, service actif inchangé
- [ ] Après `git revert` : Rollout et Application `Healthy`, `6.17.0` active

---

## Bonus 🚀
Ouvrir le tableau de bord d'Argo Rollouts (`kubectl argo rollouts dashboard`, puis `http://localhost:3100`) et comparer sa vue d'un canari en pause avec celle de l'UI ArgoCD.
