# Module 10 — Corrections

État de vérification :
- Script `ci/update-config.sh` : exécuté dans un pod `alpine:3.22` (comme un job de runner) contre un dépôt `flotte-config` de test → commit et push réussis, synchronisation ArgoCD déclenchée.
- Job `build-image` : rejoué avec `docker:28` + service `docker:28-dind` et `DOCKER_TLS_CERTDIR=/certs` (conteneur privilégié, comme les runners `saas-linux-*` de GitLab.com) → `DOCKER_HOST=tcp://docker:2376` détecté seul, construction et push réussis (client et démon 28.5.2).
- Job `update-config` : rejoué dans `alpine:3.22` avec le `before_script` du pipeline → commit `flotte-ci`, second passage sans commit (idempotent), arrêt explicite si une variable manque.
- `Jenkinsfile` : validé par le linter déclaratif de Jenkins 2.580.2 LTS.
- Non rejoué : exécution sur GitLab.com même (vérification d'identité du compte, quota de minutes) → Lab 10.1 de bout en bout le J-1 avec le compte du formateur (guide formateur).

Rattrapage : pas de script automatique (le pipeline dépend du projet GitLab de chaque stagiaire). Poste en retard : copier `labs/flotte-app/` dans `flotte-app` (Lab 10.1, étape 3) ; à défaut, simuler le job à la main :
```bash
CONFIG_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git CONFIG_TOKEN=<TOKEN> \
  NEW_IMAGE=ghcr.io/stefanprodan/podinfo:6.17.0 sh labs/flotte-app/ci/update-config.sh
```
(prérequis : `git` et `kustomize` sur le poste).

## Lab 10.1 ⭐ — Pipeline GitLab CI de `flotte-app`
### Solution
`labs/flotte-app/.gitlab-ci.yml` :
```yaml
stages:
  - build
  - update-config

variables:
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

build-image:
  stage: build
  image: docker:28
  services:
    - docker:28-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  script:
    - echo "$CI_REGISTRY_PASSWORD" |
        docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
    - docker build --build-arg GIT_SHA="$CI_COMMIT_SHA" -t "$IMAGE" .
    - docker push "$IMAGE"

update-config:
  stage: update-config
  image: alpine:3.22
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  variables:
    CONFIG_REPO_URL: $FLOTTE_CONFIG_URL
    CONFIG_TOKEN: $FLOTTE_CONFIG_TOKEN
    NEW_IMAGE: $IMAGE
  before_script:
    - apk add --no-cache git kustomize
  script:
    - sh ci/update-config.sh
```
Cœur de `ci/update-config.sh` :
```sh
git clone -q --depth 1 "$URL" "$WORK/flotte-config"
cd "$WORK/flotte-config/apps/flotte-web/overlays/dev"
kustomize edit set image "ghcr.io/stefanprodan/podinfo=${NEW_IMAGE}"
git add kustomization.yaml
git -c user.name="$COMMIT_AUTHOR" -c user.email="${COMMIT_AUTHOR}@ci.invalid" \
  commit -q -m "ci: flotte-web dev -> ${NEW_IMAGE}"
git push -q origin HEAD
```
Effet sur l'overlay (testé) :
```yaml
images:
- name: ghcr.io/stefanprodan/podinfo
  newName: registry.gitlab.com/<GITLAB_USER>/flotte-app
  newTag: <SHA_COURT>
```

### Pourquoi
- `docker:28` + service `docker:28-dind` + `DOCKER_TLS_CERTDIR` : construction d'image sur les runners hébergés de GitLab.com (runners `saas-linux-*` en mode privilégié, documentation GitLab *Hosted runners on Linux*) ; TLS entre client et démon, configuration recommandée par la documentation *Docker-in-Docker*.
- `rules` sur la branche par défaut : seules les livraisons de `main` mettent à jour `dev` ; une branche de fonctionnalité construit l'image sans la déployer.
- `kustomize edit set image` : remplace nom ET tag dans l'overlay `dev` uniquement ; la base et les autres environnements ne changent pas.
- Script idempotent : relancé sur la même image, il ne crée aucun commit.
- Commit de configuration signé `flotte-ci` : identifiable dans l'historique de `flotte-config`.
- Jeton personnel `formation-argocd` : acceptable en formation ; en entreprise, jeton propre au projet ou clé de déploiement en écriture, limitée à `flotte-config`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `Cannot connect to the Docker daemon at tcp://docker:2376` | Service `docker:28-dind` absent ou `DOCKER_TLS_CERTDIR` manquant | Recopier le bloc `build-image` |
| Job `update-config` : `Authentication failed` | Variable `FLOTTE_CONFIG_TOKEN` absente, mal nommée ou protégée sur une branche non protégée | Variables du projet ; `main` protégée |
| Job `update-config` absent | Pipeline sur une autre branche que `main` | Règle `rules` attendue |
| Pods `ImagePullBackOff` : `unauthorized` | Registre de `flotte-app` privé | Projet public (formation) ou `imagePullSecret` |
| Boucle de pipelines | `.gitlab-ci.yml` placé dans `flotte-config` | Pipeline uniquement dans `flotte-app` |

## Lab 10.2 ⭐ — De la CI au pod
### Solution
Observations attendues : nouveau commit dans `flotte-config` → `argocd app get --refresh` → canari avec image `registry.gitlab.com/<GITLAB_USER>/flotte-app:<SHA_COURT>`, analyse `Successful`, pause, promotion, `Healthy`. Le champ `status.summary.images` de l'Application porte le SHA du commit de `flotte-app`.

Durée de bout en bout (indicative) : pipeline (1 à 3 min selon les runners) + détection (jusqu'à 3 min sans webhook, ou *Refresh*) + canari (analyse 30 s, pause manuelle).

### Pourquoi
- Traçabilité à trois niveaux : commit de code (SHA) → image (tag) → commit de configuration (message) → historique ArgoCD.
- Le canari et l'analyse du M08 s'appliquent automatiquement à chaque livraison de la CI.

## Exercice 10.3 ⭐⭐ — Webhook avec secret
### Solution
```bash
kubectl patch secret argocd-secret -n argocd --type merge \
  -p '{"stringData":{"webhook.gitlab.secret":"formation-webhook-2026"}}'
SHA=$(git -C <FLOTTE_CONFIG> rev-parse HEAD)
sed -e "s/<SHA_COMPLET>/$SHA/g" -e "s/<GITLAB_USER>/$GITLAB_USER/g" labs/m10/gitlab-push.json > /tmp/push.json
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X POST https://localhost:8443/api/webhook \
  -H "Content-Type: application/json" -H "X-Gitlab-Event: Push Hook" \
  -H "X-Gitlab-Token: formation-webhook-2026" --data @/tmp/push.json
```
Résultats (testés sur v3.6.1) :
- Bon jeton : `HTTP 200` ; journal d'`argocd-server` : `refreshing app from webhook`, `Requested app '<APP>' refresh` ; date de réconciliation de l'application = instant de l'appel.
- Mauvais jeton : `HTTP 400` ; journal : `GitLab webhook token verification failed`, `X-Gitlab-Token validation failed` ; aucun rafraîchissement.

Limite constatée sur le banc de test : une application dont `repoURL` est en `git://` n'est pas rafraîchie par le webhook (`HTTP 200` mais aucune application concernée) ; les URL `https://` et `git@` de GitLab sont reconnues.

Configuration côté GitLab (ArgoCD joignable) : `flotte-config` → *Settings* → *Webhooks* → URL `https://<ARGOCD>/api/webhook`, *Secret token* = valeur de `webhook.gitlab.secret`, déclencheur *Push events* (branche `main`), vérification SSL active.

### Pourquoi
- ArgoCD rafraîchit les applications dont `repoURL` correspond au dépôt annoncé par l'événement.
- Le jeton empêche un tiers de provoquer des rafraîchissements en masse (charge du `repo-server`).
- Le webhook accélère la détection ; la réconciliation périodique reste le filet de sécurité.

## Défi 10.4 ⭐⭐⭐ — La CI attend le résultat du déploiement
### Solution
```yaml
verify-deploy:
  stage: verify
  image:
    name: quay.io/argoproj/argocd:v3.6.1
    entrypoint: [""]                   # shell du runner, pas le point d'entrée de l'image
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  variables:
    ARGOCD_SERVER: $ARGOCD_SERVER        # adresse joignable depuis le runner
    ARGOCD_AUTH_TOKEN: $ARGOCD_CI_TOKEN  # jeton du compte ci-gitlab (masqué, protégé)
  script:
    - argocd app get flotte-web-dev --refresh --grpc-web > /dev/null
    - argocd app wait flotte-web-dev --sync --health --timeout 600 --grpc-web
```
Ajouter `verify` à la liste `stages`. Commande testée depuis le poste (jeton `ci-gitlab`) :
```bash
argocd app wait flotte-api-dev --sync --health --timeout 60 \
  --auth-token "$TOKEN" --server localhost:8443 --insecure
```
Sortie : `Sync Status: Synced to 6.17.0`, `Health Status: Healthy`. Sur `flotte-web-dev` pendant un canari (20 s d'attente) :
```
{"level":"fatal","msg":"timed out (20s) waiting for app \"flotte-web-dev\" match desired state","time":"<DATE>"}
```
Code retour non nul : le job échoue, le pipeline est rouge.

Conditions en entreprise :
- Runner capable de joindre l'API ArgoCD (runner interne, ou ArgoCD exposé avec TLS et filtrage).
- Jeton `ci-gitlab` limité à `get` et `sync` sur `flotte/*` (M03), avec expiration et rotation.
- Délai maximal (`--timeout`) adapté à la durée du canari.
- Canari en pause manuelle : `app wait --health` attend tant que l'application est `Suspended` ; prévoir un délai long, ou n'attendre que `--sync`, ou automatiser la promotion par l'analyse.

## Défi 10.5 ⭐⭐⭐ — Le rendu Kubernetes dans la merge request
Script testé en local (kubectl v1.36.6, `sh` POSIX) sur la structure du Lab 09.3. Job GitLab non exécuté sur GitLab.com : [À VÉRIFIER] le J-1 avec le compte du formateur.

### Solution
`ci/diff-rendu.sh` :
```sh
#!/bin/sh
# Usage: ci/diff-rendu.sh <TARGET_REF> <OVERLAYS_DIR> > diff.md
# Renders every overlay on the current commit and on <TARGET_REF>, prints a Markdown diff
set -eu
CIBLE="$1"; DIR="$2"; TMP=$(mktemp -d)
git worktree add -q --detach "$TMP/cible" "$CIBLE"
CHANGE=0
for o in "$DIR"/*/; do
  env=$(basename "$o")
  kubectl kustomize "$o" > "$TMP/new-$env.yaml"
  if [ -d "$TMP/cible/$o" ]; then kubectl kustomize "$TMP/cible/$o" > "$TMP/old-$env.yaml"; else : > "$TMP/old-$env.yaml"; fi
  if ! diff -u "$TMP/old-$env.yaml" "$TMP/new-$env.yaml" > "$TMP/d-$env.txt"; then
    CHANGE=1
    printf '### Environnement `%s`\n\n```diff\n' "$env"; tail -n +3 "$TMP/d-$env.txt"; printf '```\n\n'
  fi
done
[ "$CHANGE" = 0 ] && echo "Aucun changement de rendu."
git worktree remove --force "$TMP/cible"; rm -rf "$TMP"
```
Test local : `./ci/diff-rendu.sh main apps/flotte-web/overlays` sur une branche `feature` → sections `dev` (`-image: ...:6.17.0` / `+image: ...:6.18.0`) et `prod` (message, `name: flotte-web-config-b7fb25f998` → `flotte-web-config-5fk9g95674`) ; rien pour `recette` ; aucun worktree résiduel.

Job (`.gitlab-ci.yml` de `flotte-config`) :
```yaml
diff-rendu:
  image: alpine:3.22
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  before_script:
    - apk add --no-cache git curl
    - curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.36.6/bin/linux/amd64/kubectl
    - chmod +x /usr/local/bin/kubectl
  script:
    - git fetch origin "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
    - sh ci/diff-rendu.sh "origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME" apps/flotte-web/overlays > diff.md
    - >
      curl -fsS --request POST --header "PRIVATE-TOKEN: $DIFF_NOTE_TOKEN"
      --data-urlencode "body@diff.md"
      "$CI_API_V4_URL/projects/$CI_PROJECT_ID/merge_requests/$CI_MERGE_REQUEST_IID/notes"
  artifacts:
    paths: [diff.md]
    expire_in: 1 week
```
`DIFF_NOTE_TOKEN` : jeton d'accès de projet, rôle *Reporter*, portée `api`, variable masquée (et protégée si les branches de MR le sont).

### Pourquoi
- Relecture du **résultat** et non de la source : une modification de base, de composant ou de version de chart devient visible environnement par environnement.
- `git worktree` : la branche cible est extraite à côté, le dossier de travail du job reste intact ; `--detach` évite de créer une branche locale.
- Nom haché de la ConfigMap : le générateur Kustomize calcule le suffixe à partir du contenu → message changé = nouveau nom, donc nouveau gabarit de pod et redéploiement (mécanisme de l'exercice 09.4).
- Sans accès au cluster : diff de rendu seulement. `argocd app diff --local` compare au cluster vivant, mais exige un runner qui joint ArgoCD (cf. Défi 10.4).
- `curl --data-urlencode "body@diff.md"` : contenu du fichier encodé, Markdown rendu dans la MR.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `fatal: invalid reference: origin/main` | Clone superficiel sans la branche cible | `git fetch origin "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"` |
| Job absent de la MR | Pipeline de branche et non de MR | Règle `merge_request_event` |
| Refus d'accès sur `/notes` | Jeton `CI_JOB_TOKEN` (API limitée à quelques points d'accès, pas les notes) [À VÉRIFIER] | Jeton d'accès de projet dédié |

## Défi 10.6 ⭐⭐⭐ — Statut de déploiement affiché sur le commit GitLab
Testé sur un cluster kind séparé (ArgoCD 3.6.1) contre un faux GitLab (récepteur `mendhak/http-https-echo:38` du Lab 07.3). Appel réel à GitLab.com : [À VÉRIFIER] le J-1 avec un jeton du formateur.

### Solution
Jeton :
```bash
kubectl patch secret argocd-notifications-secret -n argocd --type merge \
  -p '{"stringData":{"gitlab-token":"<GITLAB_TOKEN>"}}'
```
`notif-gitlab-status.yaml` (`kubectl patch cm argocd-notifications-cm -n argocd --type merge --patch-file ...`) :
```yaml
data:
  service.webhook.gitlab-status: |
    url: http://alertes-receiver.flotte-ops.svc.cluster.local/api/v4
    headers:
      - name: PRIVATE-TOKEN
        value: $gitlab-token
  template.gitlab-commit-status: |
    webhook:
      gitlab-status:
        method: POST
        path: /projects/{{index .app.metadata.annotations "hexa-mobilite/gitlab-project"}}/statuses/{{.app.status.operationState.syncResult.revision}}?state={{if eq .app.status.operationState.phase "Succeeded"}}success{{else}}failed{{end}}&name=argocd%2F{{.app.metadata.name}}&target_url={{.context.argocdUrl}}/applications/{{.app.metadata.name}}
  trigger.on-deploy-status: |
    - when: app.status.operationState != nil and app.status.operationState.phase in ['Succeeded', 'Error', 'Failed']
      oncePer: app.status.operationState.syncResult.revision
      send: [gitlab-commit-status]
  context: |
    argocdUrl: https://localhost:8443
```
Annotations de l'Application :
```yaml
metadata:
  annotations:
    hexa-mobilite/gitlab-project: "<ID_PROJET_FLOTTE_CONFIG>"
    notifications.argoproj.io/subscribe.on-deploy-status.gitlab-status: ""
```
Reçu par le faux GitLab (mesuré) :
```
"path": "/api/v4/projects/12345678/statuses/f54c636aef4d4201104ca21d75fe14d3ea23a568",
"private-token": "glpat-FAUX-JETON",
"method": "POST",
"query": {"state": "success", "name": "argocd/web-status",
          "target_url": "https://localhost:8443/applications/web-status"}
```
SHA reçu = `.status.operationState.syncResult.revision` de l'Application. GitLab.com : `url: https://gitlab.com/api/v4`, identifiant numérique du projet (*Settings* → *General*).

### Pourquoi
- Flux sortant ArgoCD → GitLab : aucun accès entrant au cluster, aucun runner dans le réseau interne (inverse du Défi 10.4, où la CI interroge ArgoCD).
- Statut posé sur le commit de `flotte-config` (révision déployée), visible dans la MR et l'historique ; `name` distinct par application → un statut par environnement.
- `oncePer: ...syncResult.revision` : une notification par révision, pas à chaque réconciliation.
- `$gitlab-token` : référence à `argocd-notifications-secret`, le jeton n'apparaît pas dans la ConfigMap.
- Une erreur `cannot fetch operationState from <nil>` peut apparaître une fois dans le journal du contrôleur de notifications à la création de l'Application (aucune opération encore) : sans effet.
- Relier au commit de **code** : reprendre le SHA de `flotte-app` écrit par la CI (tag d'image) et viser le projet `flotte-app`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Aucun appel reçu | Abonnement sans le nom du service (`subscribe.on-deploy-status.gitlab-status`) | Format `subscribe.<TRIGGER>.<SERVICE>` |
| `404 Project Not Found` (GitLab) | Chemin du projet non encodé, ou identifiant faux | Identifiant numérique, ou chemin encodé (`groupe%2Fprojet`) |
| Statut `failed` jamais envoyé | Trigger limité à `Succeeded` | Inclure `Error` et `Failed` |

## Bonus
| Étape | GitLab CI | Jenkins |
|---|---|---|
| Déclenchement | Push sur le projet | Webhook ou scrutation du dépôt (multibranch) |
| Identifiants | Variables CI/CD masquées et protégées | Magasin de credentials, `withCredentials` |
| Exécution | Image par job (`docker:28`, `alpine:3.22`) | Agent Jenkins (outils installés sur l'agent) |
| Condition de branche | `rules: if $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` | `when { branch 'main' }` (job *Multibranch Pipeline* uniquement : dans un job *Pipeline* simple, l'étape est toujours sautée) |

Argo CD Image Updater (projet `argoproj-labs`, v1.4.0 en novembre 2026) : surveille le registre et met à jour le tag selon une stratégie de version. Configuration par ressource `ImageUpdater` (CRD, depuis la v1.0 ; annotations sur l'Application = ancien mode v0.x). Écriture : `argocd` (paramètre de l'Application, par défaut, non persisté dans Git) ou `git` (commit d'un fichier `.argocd-source-<app>.yaml`, ou de la `kustomization` / des valeurs Helm, éventuellement par merge request). Limites : composant supplémentaire à exploiter, accès en lecture au registre, règles de sélection des tags, mode `argocd` non tracé dans Git.

## QCM — Réponses
1. **B** — La CI modifie le tag d'image dans `flotte-config` ; ArgoCD applique.
2. **B** — Le SHA relie l'image déployée au commit de code.
3. **C** — Écriture sur le dépôt de configuration et sur le registre ; aucun accès au cluster.
4. **B** — Le webhook déclenche le rafraîchissement immédiat des applications concernées.
5. **B** — Clé `webhook.gitlab.secret` du Secret `argocd-secret`.
6. **B** — `kustomize edit set image <NOM>=<NOUVEAU_NOM>:<TAG>`.
7. **B** — Deux dépôts distincts : le pipeline de `flotte-app` n'est pas déclenché par `flotte-config`.
