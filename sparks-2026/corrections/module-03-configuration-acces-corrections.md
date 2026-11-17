# Module 03 — Corrections

Script d'état final du module (testé sur v3.6.1) :
```bash
GITLAB_USER=<GITLAB_USER> GITLAB_DEPLOY_USER=<GITLAB_DEPLOY_USER> \
GITLAB_DEPLOY_TOKEN=<GITLAB_DEPLOY_TOKEN> ARGOCD_ADMIN_PASSWORD='<ADMIN_PASSWORD>' \
  ./scripts/m03/catch-up/m03-final-state.sh
```

## Lab 03.1 ⭐ — Personnaliser les paramètres
### Solution
Commandes de l'énoncé. Variante déclarative (fichier versionné) :
```yaml
# argocd-cm-settings.yaml
data:
  url: https://localhost:8443
  ui.bannercontent: "Cluster de formation - Hexa Mobilite"
  statusbadge.enabled: "true"
```
```bash
kubectl patch cm argocd-cm -n argocd --type merge --patch-file argocd-cm-settings.yaml
```

### Pourquoi
- Patch `merge` : seules les clés fournies sont ajoutées ou remplacées ; les clés par défaut (exclusions de ressources, `ignoreResourceUpdates`) restent en place.
- `url` : utilisée pour les redirections SSO (Défi 03.6), les liens des notifications (M07) et les badges.
- Bannière renvoyée par l'API (`/api/v1/settings`) uniquement aux utilisateurs connectés : invisible sur la page de connexion.
- Valeurs booléennes entre guillemets : une ConfigMap n'accepte que des chaînes.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| L'UI affiche soudain des Endpoints, EndpointSlices, Leases | `argocd-cm` remplacé par `kubectl apply` d'un fichier partiel | Réappliquer le manifeste d'installation (`install-argocd.sh`) puis repatcher |
| `error: unable to parse "<PATCH>": yaml: line 1` | Guillemets du JSON mal fermés dans `-p` | Utiliser `--patch-file` |
| Bannière absente | Page non rechargée, ou bannière masquée précédemment | Recharger ; une nouvelle valeur réinitialise le masquage |
| `invalid type for io.k8s.api.core.v1.ConfigMap.data: got "boolean"` | `true` sans guillemets | `"true"` |

## Lab 03.2 ⭐ — Comptes et rôles RBAC
### Solution
`scripts/m03/labs/argocd-cm-accounts.yaml` :
```yaml
data:
  accounts.dev-alice: login
  accounts.ops-bob: login
  accounts.audit-claire: login
  accounts.ci-gitlab: apiKey
```
`scripts/m03/labs/argocd-rbac-cm.yaml` (extrait `data`) :
```yaml
data:
  policy.default: ""
  scopes: "[groups]"
  policy.csv: |
    p, role:dev, applications, get, flotte/*, allow
    p, role:dev, applications, create, flotte/*, allow
    p, role:dev, applications, update, flotte/*, allow
    p, role:dev, applications, sync, flotte/*, allow
    p, role:dev, logs, get, flotte/*, allow
    p, role:dev, projects, get, flotte, allow
    p, role:ci, applications, get, flotte/*, allow
    p, role:ci, applications, sync, flotte/*, allow
    g, dev-alice, role:dev
    g, ci-gitlab, role:ci
    g, ops-bob, role:admin
    g, audit-claire, role:readonly
```
Résultats mesurés :

| Compte | `sync flotte/*` | `sync default/*` | `delete flotte/*` | `create projects` |
|---|---|---|---|---|
| `dev-alice` | yes | no | no | no |
| `audit-claire` | no | no | no | no |
| `ops-bob` | yes | yes | yes | yes |

### Pourquoi
- `policy.default: ""` : un utilisateur sans rôle ne voit rien (refus par défaut), à l'inverse de `role:readonly`.
- `role:dev` sans `delete` : suppression réservée aux ops (une suppression d'Application supprime aussi les ressources déployées).
- `logs, get` explicite : depuis 3.0, l'accès aux journaux est une ressource RBAC à part entière.
- `projects, get, flotte` : permet à `dev-alice` de voir son projet dans l'UI.
- `kubectl apply --server-side` : `argocd-rbac-cm` a été créé par un apply côté serveur (M02) ; un apply client affiche un avertissement `last-applied-configuration`.
- `argocd admin settings rbac validate` affiche un avertissement `user defined roles not found in policies: role:admin,role:readonly` : normal, ces rôles sont intégrés.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `Unauthenticated desc = invalid session: account password has changed since token issued` | Mot de passe du compte modifié après la connexion | `argocd login` à nouveau |
| `account '<nom>' does not exist` | Patch de `argocd-cm` non appliqué ou faute de frappe | `argocd account list` |
| `can-i` répond `yes` partout | `policy.default: role:readonly` ou `role:admin` | Vider `policy.default` |
| `dev-alice` ne voit pas son projet dans l'UI | Règle `projects, get` absente | Ajouter la règle |
| `Policy is invalid` | Virgule manquante ou ressource inconnue (`application` au lieu de `applications`) | Corriger la ligne indiquée |

## Exercice 03.3 ⭐⭐ — Audit et jeton CI
### Solution
```bash
argocd login localhost:8443 --username audit-claire --password 'Mdp-audit-claire-2026' \
  --insecure --name claire
argocd account can-i get applications 'flotte/x'
argocd account can-i get logs 'flotte/x'
argocd account can-i sync applications 'flotte/x'
argocd account can-i create projects '*'
argocd context localhost:8443
```
Sortie attendue (4 dernières réponses) : `yes`, `yes`, `no`, `no`.
```bash
TOKEN=$(argocd account generate-token --account ci-gitlab --expires-in 168h --id formation)
argocd account get --account ci-gitlab
argocd app list --auth-token "$TOKEN"
argocd login localhost:8443 --username ci-gitlab --password x --insecure
argocd account delete-token --account ci-gitlab formation
TOKEN=$(argocd account generate-token --account ci-gitlab --expires-in 168h --id formation)
```
Sorties attendues :
```
Tokens:
ID         ISSUED AT                  EXPIRING AT
formation  2026-11-08T13:14:48+01:00  2026-11-15T13:14:48+01:00
NAME  CLUSTER  NAMESPACE  PROJECT  STATUS  HEALTH  SYNCPOLICY  CONDITIONS  REPO  PATH  TARGET
{"level":"fatal","msg":"rpc error: code = Unauthenticated desc = Invalid username or password"}
```
Après `delete-token`, `argocd account get --account ci-gitlab` affiche `Tokens:` puis `NONE`.

### Pourquoi
- `role:readonly` inclut `logs, get` (politique intégrée 3.6) : l'audit consulte les journaux sans pouvoir agir.
- Compte `apiKey` sans `login` : aucun mot de passe, donc aucune connexion interactive possible.
- Jeton avec identifiant (`--id`) et expiration : révocable individuellement, durée de vie limitée.
- `app list` vide pour `ci-gitlab` : normal, aucune application dans `flotte` à ce stade.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `generate-token` : `account does not have 'apiKey' capability` | Capacité `login` seule | `accounts.ci-gitlab: apiKey` |
| `can-i create projects *` affiche l'aide de la commande | Joker `*` non protégé, développé par le shell | `'*'` entre apostrophes |
| Jeton refusé | Jeton révoqué ou expiré | `argocd account get --account ci-gitlab` |

## Lab 03.4 ⭐ — Projet `flotte` et dépôt privé
### Solution
Commandes de l'énoncé. Fichiers modèles : `scripts/m03/labs/appproject-flotte.yaml`, `scripts/m03/labs/repo-flotte-config.yaml`.

Équivalent CLI du dépôt (sans fichier) :
```bash
argocd repo add https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  --username <GITLAB_DEPLOY_USER> --password <GITLAB_DEPLOY_TOKEN> --project flotte
```

### Pourquoi
- Jeton de déploiement GitLab : propre au projet, lecture seule, sans lien avec un compte personnel (départ d'un collaborateur sans impact).
- `project: flotte` dans le Secret : dépôt *scopé*, utilisable uniquement par les applications du projet.
- `clusterResourceWhitelist` limité à `Namespace` : l'option `CreateNamespace=true` fonctionne, mais aucune ClusterRole ou CRD ne peut être déployée par l'équipe.
- `orphanedResources.warn` : signale les ressources présentes dans les namespaces `flotte-*` mais absentes de Git.
- Fichier contenant le jeton supprimé : le Secret ne doit jamais être poussé en clair dans Git (chiffrement au M11).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `STATUS` = `Failed`, `authentication required: HTTP Basic: Access denied` | Nom d'utilisateur ou jeton faux, jeton expiré | Vérifier `gitlab+deploy-token-<N>` et la valeur, recréer le jeton si besoin |
| `STATUS` = `Failed`, `repository not found` | URL fausse (groupe, `.git` manquant) | Copier l'URL HTTPS depuis le bouton *Code* |
| Dépôt absent de `argocd repo list` | Étiquette `argocd.argoproj.io/secret-type` manquante | Vérifier le bloc `labels` |
| Variables `${GITLAB_USER}` restées dans le fichier | `export` oublié avant `sed` | `grep '\${' /tmp/*.yaml` |

## Exercice 03.5 ⭐⭐ — Éprouver les frontières du projet
### Solution
```bash
argocd context alice
R=https://gitlab.com/<GITLAB_USER>/flotte-config.git
D="--dest-server https://kubernetes.default.svc"
argocd app create test-ok --project flotte --repo $R --path . $D \
  --dest-namespace flotte-dev --sync-option CreateNamespace=true
argocd app create test-ns --project flotte --repo $R --path . $D --dest-namespace default
argocd app create test-repo --project flotte \
  --repo https://github.com/argoproj/argocd-example-apps.git --path guestbook \
  $D --dest-namespace flotte-dev
argocd app create test-projet --project default --repo $R --path . $D --dest-namespace flotte-dev
argocd app delete test-ok --yes
argocd context localhost:8443 && argocd app delete test-ok --yes
```

| Tentative | Résultat | Barrière |
|---|---|---|
| `test-ok` | `application 'test-ok' created` | — |
| `test-ns` | `InvalidSpecError: application destination server 'https://kubernetes.default.svc' and namespace 'default' do not match any of the allowed destinations in project 'flotte'` | Projet |
| `test-repo` | `InvalidSpecError: application repo https://github.com/argoproj/argocd-example-apps.git is not permitted in project 'flotte'` | Projet |
| `test-projet` | `PermissionDenied desc = permission denied: applications, create, default/test-projet, sub: dev-alice` | RBAC |
| Suppression de `test-ok` | `PermissionDenied desc = permission denied: applications, delete, flotte/test-ok, sub: dev-alice` | RBAC |

`test-ok` reste sans ressource : le dépôt ne contient encore qu'un README (manifestes ajoutés au M04). Statut affiché pour un chemin sans manifeste (testé) : `Synced` et `Healthy`, aucune ressource, aucune condition d'erreur ; une synchronisation répond `successfully synced (no more tasks)`.

### Pourquoi
- Le RBAC est évalué d'abord (droit d'agir sur `<projet>/<application>`), puis la conformité de la spécification au projet.
- Projet = garde-fou même pour un utilisateur à droits larges : un `role:admin` ne peut pas non plus déployer hors des destinations du projet choisi.

### Variantes acceptables
- Créations par l'UI (*New App*) : mêmes messages dans un bandeau d'erreur.

## Défi 03.6 ⭐⭐⭐ — Connexion SSO GitLab avec Dex
Testé sur le banc jusqu'à GitLab.com (application OAuth fictive) : connecteur publié par `/api/v1/settings`, redirection `ArgoCD → /api/dex/auth/gitlab → https://gitlab.com/oauth/authorize` avec `redirect_uri=https://localhost:8443/api/dex/callback` et `scope=read_user openid`. Connexion avec un compte réel : à rejouer le J-1 avec une application OAuth du formateur.

### Solution
1. GitLab : *Edit profile* → *Applications* → nom `argocd-formation`, URL de rappel `https://localhost:8443/api/dex/callback`, portées `read_user` et `openid`. Noter l'*Application ID* et le *Secret*.
2. Secret client dans `argocd-secret` :
   ```bash
   kubectl patch secret argocd-secret -n argocd --type merge \
     -p '{"stringData":{"dex.gitlab.clientSecret":"<GITLAB_OAUTH_SECRET>"}}'
   ```
3. Connecteur dans `argocd-cm` (`url` déjà définie au Lab 03.1) :
   ```yaml
   data:
     dex.config: |
       connectors:
         - type: gitlab
           id: gitlab
           name: GitLab
           config:
             baseURL: https://gitlab.com
             clientID: <GITLAB_OAUTH_APP_ID>
             clientSecret: $dex.gitlab.clientSecret
   ```
   ```bash
   kubectl patch cm argocd-cm -n argocd --type merge --patch-file dex-gitlab.yaml
   ```
4. RBAC : ajouter à `policy.csv` la ligne `g, <EMAIL_GITLAB>, role:readonly` (ou `g, <GROUPE_GITLAB>, role:readonly`), puis réappliquer.
5. Connexion : bouton *Log in via GitLab* dans l'UI, ou `argocd login localhost:8443 --sso --insecure`.

### Pourquoi
- `redirectURI` non renseigné : ArgoCD le calcule à partir de `url` (`/api/dex/callback`).
- `$dex.gitlab.clientSecret` : référence à une clé de `argocd-secret`, le secret n'apparaît pas dans la ConfigMap.
- `scopes: "[groups]"` (Lab 03.2) : les groupes GitLab transmis par Dex sont utilisables dans les lignes `g`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `The redirect URI included is not valid` (GitLab) | URL de rappel différente de `url` + `/api/dex/callback` | Aligner les deux URL |
| Bouton GitLab absent | `dex.config` mal indenté | `kubectl logs deploy/argocd-dex-server -n argocd` |
| Connexion réussie, aucune application visible | Aucune ligne `g` pour l'utilisateur, `policy.default` vide | Ajouter la ligne RBAC (identifiant = e-mail ou groupe selon la configuration) |

## Défi 03.7 ⭐⭐⭐ — Politique RBAC testée comme du code
Testé hors cluster avec ArgoCD 3.6.1 : 10 cas sur 10 conformes.

### Solution
`policy.csv` :
```csv
p, role:dev, applications, get, flotte/*, allow
p, role:dev, applications, create, flotte/*, allow
p, role:dev, applications, update, flotte/*, allow
p, role:dev, applications, sync, flotte/*, allow
p, role:dev, logs, get, flotte/*, allow
p, role:dev, projects, get, flotte, allow
p, role:dev, applications, sync, flotte/*-prod, deny
p, role:dev, applications, update, flotte/*-prod, deny
g, role:ops, role:readonly
p, role:ops, applications, *, */*, allow
p, role:ops, projects, *, *, allow
p, role:ops, projects, delete, *, deny
g, dev-alice, role:dev
g, ops-bob, role:ops
```
`test-rbac.sh` :
```bash
#!/usr/bin/env bash
# Usage: ./test-rbac.sh <POLICY_FILE> - RBAC matrix, exit 1 on any mismatch
set -u
POLICY="${1:-policy.csv}"; FAIL=0
check() { # check <yes|no> <subject> <action> <resource> <object>
  got=$(argocd admin settings rbac can "$2" "$3" "$4" "$5" --policy-file "$POLICY" 2>/dev/null \
        | tail -1 | tr '[:upper:]' '[:lower:]')
  if [ "$got" = "$1" ]; then echo "OK   $2 $3 $4 $5 -> $got"
  else echo "FAIL $2 $3 $4 $5 -> $got (attendu $1)"; FAIL=1; fi
}
check yes dev-alice sync   applications flotte/flotte-web
check no  dev-alice sync   applications flotte/flotte-web-prod
check no  dev-alice update applications flotte/flotte-web-prod
check yes dev-alice get    applications flotte/flotte-web-prod
check no  dev-alice sync   applications default/guestbook
check yes ops-bob   delete applications default/guestbook
check yes ops-bob   create projects     demo
check no  ops-bob   delete projects     flotte
check yes ops-bob   get    clusters     https://kubernetes.default.svc
check no  ops-bob   update clusters     https://kubernetes.default.svc
exit $FAIL
```
Sortie mesurée : 10 lignes `OK`, code retour `0`. Ligne `p, role:ops, projects, delete, *, deny` retirée → `FAIL ops-bob delete projects flotte -> yes (attendu no)`, code retour `1`.

### Pourquoi
- `deny` prioritaire sur `allow` (effet `some(allow) && !some(deny)` du modèle Casbin d'ArgoCD) : une exception s'écrit sans réécrire les règles générales.
- `g, role:ops, role:readonly` : héritage de rôle ; `get clusters` vient de `role:readonly`, `update clusters` n'est accordé nulle part → refus.
- Correspondance glob : `flotte/*-prod` couvre `flotte/flotte-web-prod`, pas `flotte/flotte-web`.
- `rbac can --policy-file` : aucun cluster nécessaire → test exécutable dans un job CI avant fusion (même image que la CLI).
- Avertissement `role:readonly` de `validate` : rôle intégré, normal (cf. Lab 03.2).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `sync flotte/flotte-web-prod` → yes | Règle `deny` écrite `flotte-web-prod` (sans projet) | Objet d'application = `<PROJET>/<APP>` |
| Toutes les réponses `no` pour `ops-bob` | Ligne `g, ops-bob, role:ops` absente ou rôle mal orthographié | `validate` : warning `roles not found` sur un rôle personnalisé = faute de frappe |
| Script toujours `OK` | Comparaison sur `Yes` / `No` sans normalisation de casse | `tr '[:upper:]' '[:lower:]'` |

## Défi 03.8 ⭐⭐⭐ — Synchroniser sous un compte de service limité
Testé sur un cluster kind séparé (ArgoCD 3.6.1, Kubernetes 1.36) avec `argocd-example-apps` (`guestbook` autorisé, `pre-post-sync` refusé à cause de ses Jobs).

### Solution
1. Activer l'impersonation :
   ```bash
   kubectl patch cm argocd-cm -n argocd --type merge \
     -p '{"data":{"application.sync.impersonation.enabled":"true"}}'
   ```
2. Compte de service et droits (`flotte-deployer.yaml`) :
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata: {name: flotte-deployer, namespace: flotte-dev}
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata: {name: flotte-deployer, namespace: flotte-dev}
   rules:
     - apiGroups: ["apps"]
       resources: ["deployments"]
       verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
     - apiGroups: [""]
       resources: ["services", "configmaps"]
       verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata: {name: flotte-deployer, namespace: flotte-dev}
   roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: flotte-deployer}
   subjects: [{kind: ServiceAccount, name: flotte-deployer, namespace: flotte-dev}]
   ```
3. Association dans le projet :
   ```bash
   kubectl patch appproj flotte -n argocd --type merge -p '{"spec":{"destinationServiceAccounts":[
     {"server":"https://kubernetes.default.svc","namespace":"flotte-dev","defaultServiceAccount":"flotte-deployer"}]}}'
   ```
4. Synchroniser l'application du fil rouge → `successfully synced (all tasks run)`.
5. Ajouter un Job dans `flotte-config`, pousser, synchroniser → phase `Failed` :
   ```
   jobs.batch "<NOM>" is forbidden: User "system:serviceaccount:flotte-dev:flotte-deployer"
   cannot get resource "jobs" in API group "batch" in the namespace "flotte-dev"
   ```
6. Retirer le Job de `flotte-config`, puis revenir à l'état initial :
   ```bash
   kubectl patch appproj flotte -n argocd --type json -p '[{"op":"remove","path":"/spec/destinationServiceAccounts"}]'
   kubectl patch cm argocd-cm -n argocd --type merge -p '{"data":{"application.sync.impersonation.enabled":"false"}}'
   kubectl delete -f flotte-deployer.yaml
   ```

### Pourquoi
- Impersonation active : le contrôleur applique les manifestes avec l'identité `system:serviceaccount:<NS>:<SA>` ; le RBAC Kubernetes devient la barrière, en plus de l'AppProject.
- `defaultServiceAccount` sans préfixe : compte cherché dans le namespace de destination (`<NS>:<SA>` pour un autre namespace).
- Projet sans entrée correspondante → refus explicite `no matching service account found for destination server ... and namespace ...` (mesuré) : aucun repli silencieux sur `cluster-admin`.
- Échec en `dry run` : aucun objet partiellement appliqué.
- Retour à l'état initial indispensable : les hooks du M05 créent des Jobs, refusés par ce Role.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Ressources autorisées refusées aussi | RoleBinding dans un autre namespace, ou `subjects` sans `namespace` | `kubectl auth can-i create deployments -n flotte-dev --as system:serviceaccount:flotte-dev:flotte-deployer` |
| Aucun changement de comportement | Clé d'activation mal orthographiée, ou valeur `true` sans guillemets | `kubectl get cm argocd-cm -n argocd -o yaml \| grep impersonation` |
| Toutes les synchronisations du projet `default` échouent | Impersonation globale : chaque destination doit avoir un compte | Désactiver en fin de défi, ou déclarer un compte pour chaque projet utilisé |

## Bonus
```bash
argocd account can-i create projects '*' --argocd-context <CONTEXTE_OPS_BOB>
kubectl patch cm argocd-cm -n argocd --type merge -p '{"data":{"admin.enabled":"false"}}'
argocd login localhost:8443 --username admin --insecure
```
Sortie attendue (dernière commande) :
```
{"level":"fatal","msg":"rpc error: code = Unauthenticated desc = Account admin is disabled"}
```
Réactivation : `kubectl patch cm argocd-cm -n argocd --type merge -p '{"data":{"admin.enabled":"true"}}'`.

## QCM — Réponses
1. **B** — En 3.x, `argocd-cm` contient des exclusions et personnalisations par défaut ; un apply partiel les supprime.
2. **C** — `argocd-cmd-params-cm` est lu au démarrage des composants : redémarrage nécessaire.
3. **B** — `apiKey` permet de générer des jetons sans connexion interactive.
4. **B** — Une ligne `g` attribue un rôle (ou un groupe) à un sujet ; le compte est déclaré dans `argocd-cm`.
5. **B** — Pour applications, applicationsets, logs et exec, l'objet est `<projet>/<application>`.
6. **B** — La destination `default` ne correspond pas au motif `flotte-*` du projet : `InvalidSpecError`.
7. **B** — Depuis 3.0, la déclaration des dépôts dans `argocd-cm` est supprimée ; seuls les Secrets étiquetés subsistent.
8. **C** — Le projet `default` autorise tous les dépôts, destinations et ressources : à restreindre en production.
