# Module 11 — Exercices

Fichiers fournis : `labs/m11/` (projet `flotte` avec rôle, durcissement d'`argocd-cm`, exemple OIDC). Contexte CLI administrateur : `argocd context localhost:8443`.

## Lab 11.1 ⭐ — Sceller le premier secret (guidé)
**Durée** : 20 min · **Objectif** : fournir une clé d'API à `flotte-web` sans jamais l'écrire en clair dans Git
**Contexte** : `flotte-web` doit appeler un service partenaire avec la clé `FLOTTE_API_KEY` ; l'audit interdit tout secret lisible dans Git.
**Prérequis** : état final du M10 ; CLI `kubeseal` v0.41.2 installée (préparation du poste)

Variables : `<VALEUR>` = clé fictive choisie (ex. `hexa-dev-0001`).

### Étapes
1. Installer le contrôleur Sealed Secrets (équipe ops).
   ```bash
   kubectl apply --server-side \
     -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.41.2/controller.yaml
   kubectl rollout status deploy/sealed-secrets-controller -n kube-system
   kubeseal --version
   ```
   Résultat attendu : `deployment "sealed-secrets-controller" successfully rolled out`, puis `kubeseal version: 0.41.2`.
2. Sceller le secret pour `flotte-dev` (aucun Secret créé dans le cluster).
   ```bash
   cd <FLOTTE_CONFIG>
   kubectl create secret generic flotte-web-secrets -n flotte-dev \
     --from-literal=FLOTTE_API_KEY=<VALEUR> --dry-run=client -o yaml \
     | kubeseal --format yaml > apps/flotte-web/overlays/dev/sealed-secret.yaml
   grep -c '<VALEUR>' apps/flotte-web/overlays/dev/sealed-secret.yaml
   ```
   Résultat attendu : `0` (la valeur n'apparaît pas dans le fichier).
3. Déclarer le fichier dans l'overlay et référencer le Secret dans la base.
   - `apps/flotte-web/overlays/dev/kustomization.yaml` : ajouter `sealed-secret.yaml` sous `resources`.
   - `apps/flotte-web/base/rollout.yaml` : sous `envFrom`, ajouter :
   ```yaml
               - secretRef:
                   name: flotte-web-secrets
                   optional: true
   ```
4. Vérifier le rendu, committer, pousser, livrer.
   ```bash
   kubectl kustomize apps/flotte-web/overlays/dev | grep -E 'kind: SealedSecret|secretRef' -A1
   git add -A && git commit -m "feat: cle API scellee pour dev" && git push
   argocd app get flotte-web-dev --refresh > /dev/null
   kubectl argo rollouts promote flotte-web -n flotte-dev --full
   argocd app wait flotte-web-dev --health
   ```
5. Vérifier le Secret créé par le contrôleur et la variable dans les pods.
   ```bash
   kubectl get secret flotte-web-secrets -n flotte-dev -o jsonpath='{.metadata.ownerReferences[0].kind}{"\n"}'
   P=$(kubectl get pods -n flotte-dev -l app.kubernetes.io/name=flotte-web -o name | head -1)
   kubectl exec -n flotte-dev "$P" -- sh -c 'echo FLOTTE_API_KEY=$FLOTTE_API_KEY'
   ```
   Résultat attendu :
   ```
   SealedSecret
   FLOTTE_API_KEY=<VALEUR>
   ```

### Critères de réussite
- [ ] Aucune valeur en clair dans `flotte-config`
- [ ] SealedSecret `Synced` / `Healthy` dans ArgoCD ; Secret possédé par le SealedSecret
- [ ] Variable présente dans les pods de `dev` ; `recette` démarre sans ce secret

---

## Exercice 11.2 ⭐⭐ — Portée et sauvegarde de la clé (semi-autonome)
**Durée** : 10 min · **Objectif** : comprendre ce que protège Sealed Secrets et ce qui peut le rendre inutilisable
**Contexte** : l'audit demande ce qu'il se passe si un SealedSecret est copié dans un autre namespace, et comment survivre à la perte du cluster.

**Énoncé** :
- Appliquer le SealedSecret de `dev` dans le namespace `flotte-recette` (copie modifiée, hors Git) ; relever l'état du SealedSecret et l'existence du Secret ; supprimer la copie.
- Exporter la clé privée du contrôleur dans un fichier, expliquer où le stocker et pourquoi.
- Sceller la même clé d'API pour `flotte-recette` et l'ajouter à l'overlay `recette`.

**Indices** : `kubectl get sealedsecret -o jsonpath='{.status.conditions[0].message}'` ; clés du contrôleur = Secrets étiquetés `sealedsecrets.bitnami.com/sealed-secrets-key` dans `kube-system`.

**Critères de réussite** :
- [ ] Message `no key could decrypt secret` relevé, aucun Secret créé
- [ ] Sauvegarde de la clé réalisée et lieu de stockage justifié (hors cluster, hors Git)
- [ ] Recette : SealedSecret propre, variable présente après promotion

---

## Lab 11.3 ⭐ — Rôle de projet pour la CI (guidé)
**Durée** : 10 min · **Objectif** : remplacer le compte global `ci-gitlab` par un rôle limité au projet `flotte`
**Contexte** : l'équipe dev veut gérer elle-même les jetons de ses pipelines, sans toucher au RBAC global.
**Prérequis** : Lab 03.2 (compte `ci-gitlab`)

### Étapes
1. Créer le rôle et ses règles.
   ```bash
   argocd proj role create flotte ci-deployer --description "Pipeline CI"
   argocd proj role add-policy flotte ci-deployer --action get --permission allow --object '*'
   argocd proj role add-policy flotte ci-deployer \
     --action sync --permission allow --object 'flotte-*'
   argocd proj role get flotte ci-deployer
   ```
   Résultat attendu (règles) :
   ```
   p, proj:flotte:ci-deployer, applications, get, flotte/*, allow
   p, proj:flotte:ci-deployer, applications, sync, flotte/flotte-*, allow
   ```
2. Créer un jeton de 7 jours et l'utiliser.
   ```bash
   PT=$(argocd proj role create-token flotte ci-deployer --expires-in 168h --token-only)
   argocd app sync flotte-api-dev --auth-token "$PT" | grep -E 'Phase|Message'
   argocd app delete flotte-api-dev --auth-token "$PT" --yes
   ```
   Résultat attendu : `Phase: Succeeded`, `Message: successfully synced (all tasks run)`, puis `permission denied` pour la suppression.
3. Reporter le rôle dans la définition versionnée du projet : comparer avec `labs/m11/appproject-flotte-roles.yaml`.

### Critères de réussite
- [ ] Synchronisation autorisée, suppression refusée avec le jeton du rôle
- [ ] Rôle présent dans le fichier versionné du projet

---

## Exercice 11.4 ⭐⭐ — Durcir ArgoCD (semi-autonome)
**Durée** : 10 min · **Objectif** : appliquer la liste de contrôle de durcissement sans se bloquer dehors
**Contexte** : avant la mise en production, l'équipe ops applique les recommandations de l'audit.

**Énoncé** :
- Vérifier que `ops-bob` dispose de tous les droits (`can-i`), puis appliquer `labs/m11/argocd-cm-hardening.yaml` (patch `merge`).
- Prouver : `admin` refusé, `ops-bob` accepté, onglet *Terminal* absent de l'UI.
- Relever les réglages déjà conformes par défaut et ceux qui ne le sont pas (tableau de la slide « Durcir l'installation »).
- Réactiver `admin` en fin d'exercice (scripts de rattrapage).

**Critères de réussite** :
- [ ] Connexion `admin` : `Account admin is disabled` ; `ops-bob` connecté
- [ ] Tableau défaut / production complété
- [ ] `admin` réactivé

---

## Défi 11.5 ⭐⭐⭐ — Registre privé et secret de téléchargement (autonome)
**Durée** : 15 min (en autonomie si le temps manque) · **Objectif** : repasser `flotte-app` en privé sans casser les déploiements
**Contexte** : au M10, le projet `flotte-app` a été rendu public pour simplifier ; la sécurité exige un registre privé.

**Énoncé** :
- Créer dans `flotte-app` un jeton de déploiement de portée `read_registry`.
- Produire un Secret de type `kubernetes.io/dockerconfigjson` pour `registry.gitlab.com`, le sceller pour `flotte-dev`, l'ajouter à l'overlay `dev`.
- Référencer ce secret dans le modèle de pod (`imagePullSecrets`) par un patch de l'overlay `dev`.
- Repasser `flotte-app` en privé et prouver qu'une nouvelle livraison CI est toujours déployée.

**Critères de réussite** :
- [ ] Aucun identifiant de registre en clair dans Git
- [ ] Projet `flotte-app` privé, image téléchargée par le cluster
- [ ] Explication : pourquoi ce secret est propre à chaque namespace

---

## Bonus 🚀
Lire l'exemple `labs/m11/oidc-config-example.yaml` et le comparer au connecteur Dex GitLab du Défi 03.6 : quel composant d'ArgoCD est utilisé dans chaque cas, où vit le secret client, comment les groupes arrivent dans le RBAC.
