# Module 04 — Corrections

Script d'état final du module (testé sur v3.6.1) :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m04/catch-up/m04-final-state.sh
```

## Lab 04.1 ⭐ — Manifestes de `flotte-web` dans Git
### Solution
Fichiers de référence : `labs/flotte-config/apps/flotte-web/`.

`deployment.yaml` :
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flotte-web
  labels:
    app.kubernetes.io/name: flotte-web
    app.kubernetes.io/part-of: hexa-mobilite
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: flotte-web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: flotte-web
        app.kubernetes.io/part-of: hexa-mobilite
    spec:
      containers:
        - name: flotte-web
          image: ghcr.io/stefanprodan/podinfo:6.15.0
          ports:
            - name: http
              containerPort: 9898
          envFrom:
            - configMapRef:
                name: flotte-web-config
          readinessProbe:
            httpGet: {path: /readyz, port: http}
          livenessProbe:
            httpGet: {path: /healthz, port: http}
          resources:
            requests: {cpu: 50m, memory: 32Mi}
            limits: {memory: 128Mi}
```
`service.yaml` : Service `flotte-web`, port 80 vers le port nommé `http`. `configmap.yaml` : `PODINFO_UI_MESSAGE` et `PODINFO_UI_COLOR`, variables lues par podinfo.

### Pourquoi
- `--dry-run=server` : validation par l'API server (schéma, champs inconnus) sans création ; plus fiable que `--dry-run=client`.
- `-n default` uniquement pour la validation : aucun namespace dans les manifestes, il est fourni par la destination de l'Application.
- Port nommé `http` : le Service et les sondes ne dépendent pas du numéro de port.
- Pas de limite CPU : évite le bridage (*throttling*) ; limite mémoire conservée (protection du nœud).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `strict decoding error: unknown field` | Faute d'indentation ou de nom de champ | Message indique le champ ; comparer au fichier de référence |
| `the server could not find the requested resource` | `apiVersion` erronée | `kubectl api-resources \| grep -i deploy` |
| `git push` refusé (`protected branch`) | Branche `main` protégée sans droit de push | Paramètres GitLab du projet, ou merge request |

## Lab 04.2 ⭐ — Application déclarative et premier déploiement
### Solution
`argocd/flotte-web-dev.yaml` :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-web-dev
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: flotte
  source:
    repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
    targetRevision: main
    path: apps/flotte-web
  destination:
    server: https://kubernetes.default.svc
    namespace: flotte-dev
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```
Sortie de synchronisation (testée) :
```
GROUP  KIND        NAMESPACE   NAME               STATUS   HEALTH       HOOK  MESSAGE
       Namespace               flotte-dev         Running  Synced             namespace/flotte-dev created
       ConfigMap   flotte-dev  flotte-web-config  Synced                      configmap/flotte-web-config created
       Service     flotte-dev  flotte-web         Synced   Healthy            service/flotte-web created
apps   Deployment  flotte-dev  flotte-web         Synced   Progressing        deployment.apps/flotte-web created
```
Après `app wait --health` : `Synced` / `Healthy`, Deployment `2/2`.

### Pourquoi
- Application créée par `admin` (création d'Applications réservée aux ops dans l'organisation cible), synchronisée par `dev-alice` (`sync` autorisé sur `flotte/*`).
- `Progressing` juste après la synchronisation : les pods démarrent ; `app wait --health` attend `Healthy`.
- ConfigMap sans colonne `HEALTH` : aucune évaluation de santé pour ce type de ressource.
- Fichier d'Application dans `flotte-config/argocd/` : l'Application elle-même est versionnée (reconstruction possible, base de l'*App of Apps* au M12).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `application repo <URL> is not permitted in project 'flotte'` | `<GITLAB_USER>` non remplacé, ou URL différente de `sourceRepos` (`.git`, casse) | `grep repoURL argocd/flotte-web-dev.yaml` ; URL identique à celle du projet |
| `InvalidSpecError: Unable to generate manifests in <CHEMIN>` (`app path does not exist`) | `path` faux ou commit non poussé | `git push`, vérifier le chemin dans GitLab |
| `Namespace "flotte-dev" not found` à la synchronisation | Option `CreateNamespace=true` absente | Ajouter l'option dans `syncOptions` |
| `PermissionDenied desc = permission denied: applications, sync` | Contexte `alice` absent ou session expirée | `argocd context alice`, sinon `argocd login localhost:8443 --username dev-alice --insecure --name alice` |
| Pods `ImagePullBackOff` | Réseau ou tag d'image faux | `kubectl describe pod -n flotte-dev` |

## Exercice 04.3 ⭐⭐ — Aperçu d'un chart Helm
### Solution
```bash
argocd context localhost:8443
argocd proj add-source flotte https://stefanprodan.github.io/podinfo
```
`argocd/flotte-web-helm.yaml` :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-web-helm
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: flotte
  source:
    repoURL: https://stefanprodan.github.io/podinfo
    chart: podinfo
    targetRevision: 6.16.0
    helm:
      releaseName: flotte-web
      valuesObject:
        replicaCount: 1
        ui:
          message: "Hexa Mobilite - apercu Helm"
  destination:
    server: https://kubernetes.default.svc
    namespace: flotte-preview
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```
```bash
kubectl apply -f argocd/flotte-web-helm.yaml
argocd app manifests flotte-web-helm --source git | grep -E '^kind:|image:'
argocd app sync flotte-web-helm && argocd app wait flotte-web-helm --health
helm list -A
argocd app delete flotte-web-helm --yes
kubectl get deploy -n flotte-preview
```
Sorties attendues :
```
kind: Service
kind: Deployment
        image: ghcr.io/stefanprodan/podinfo:6.16.0
Sync Status:        Synced to 6.16.0
Health Status:      Healthy
NAME	NAMESPACE	REVISION	UPDATED	STATUS	CHART	APP VERSION
No resources found in flotte-preview namespace.
```

### Pourquoi
- `repoURL` d'un dépôt de charts + `chart` : ArgoCD télécharge l'archive du chart, aucun dépôt Git n'est nécessaire.
- `targetRevision` = version du chart (`6.16.0`), pas une branche.
- `valuesObject` : valeurs écrites en YAML structuré (validé), préférable à `values` (chaîne de texte).
- Namespace `flotte-preview` conservé après suppression de l'Application : créé par l'option `CreateNamespace`, il n'est pas suivi comme ressource de l'application (`kubectl delete namespace flotte-preview` si besoin).
- `helm list` vide : ArgoCD utilise Helm comme moteur de rendu uniquement ; le cycle de vie est géré par ArgoCD (historique dans ArgoCD, pas dans Helm).
- Nom des ressources `flotte-web-podinfo` : `releaseName` + nom du chart (convention du chart).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `application repo https://stefanprodan.github.io/podinfo is not permitted` | Source non ajoutée au projet | `argocd proj add-source` (contexte administrateur) |
| `chart podinfo version 6.16 not found` | Version incomplète | Version exacte `6.16.0` |
| Valeurs ignorées | `valuesObject` mal indenté, ou clé inexistante dans le chart | `helm show values podinfo --repo https://stefanprodan.github.io/podinfo` |
| `PermissionDenied desc = permission denied: projects, update` | Commande lancée dans le contexte `alice` | `argocd context localhost:8443` |

### Variantes acceptables
- `argocd app create flotte-web-helm --repo https://stefanprodan.github.io/podinfo --helm-chart podinfo --revision 6.16.0 --helm-set replicaCount=1 --dest-namespace flotte-preview` (plus `--dest-server`, `--project`) : même résultat, sans trace dans Git.
- `helm.parameters` (liste nom / valeur) au lieu de `valuesObject`.

## Défi 04.4 ⭐⭐⭐ — Kustomize distant et révision figée
### Solution
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-web-kustomize
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: flotte
  source:
    repoURL: https://github.com/stefanprodan/podinfo.git
    targetRevision: 6.17.0
    path: kustomize
  destination:
    server: https://kubernetes.default.svc
    namespace: flotte-kust
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```
Prérequis : `argocd proj add-source flotte https://github.com/stefanprodan/podinfo.git`.

Ressources créées (testé) :
```
GROUP        KIND                     NAMESPACE    NAME         STATUS   HEALTH
             Namespace                             flotte-kust  Running  Synced
             Service                  flotte-kust  podinfo      Synced   Healthy
apps         Deployment               flotte-kust  podinfo      Synced   Healthy
autoscaling  HorizontalPodAutoscaler  flotte-kust  podinfo      Synced   Healthy
```
- Ressource supplémentaire : `HorizontalPodAutoscaler`, qui ajuste le nombre de réplicas selon la charge.
- `targetRevision: master` : chaque commit sur la branche serait déployé (après réconciliation), sans revue de l'équipe *Hexa Mobilité* ; le tag `6.17.0` fige le contenu (tant que le tag n'est pas déplacé).

### Pourquoi
- Présence de `kustomization.yaml` dans `kustomize/` : rendu Kustomize automatique.
- Dépôt tiers suivi sur une branche = dépendance non maîtrisée : en entreprise, copie interne (*vendoring*) ou tag figé.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `unable to resolve '6.17' to a commit SHA` | Tag inexistant | `git ls-remote --tags https://github.com/stefanprodan/podinfo.git` |
| Application `Degraded` pendant la suppression | Ressources en cours d'arrêt | Attendre la fin de `argocd app delete` |

## Défi 04.5 ⭐⭐⭐ — Applications déclarées dans le namespace de l'équipe
Testé sur un cluster kind séparé (ArgoCD 3.6.1, dépôt Git interne au cluster à la place de `flotte-config`).

### Solution
1. Namespace surveillé, puis redémarrage :
   ```bash
   kubectl patch cm argocd-cmd-params-cm -n argocd --type merge \
     -p '{"data":{"application.namespaces":"flotte-apps"}}'
   kubectl rollout restart deploy/argocd-server -n argocd
   kubectl rollout restart sts/argocd-application-controller -n argocd
   kubectl create namespace flotte-apps
   ```
2. Application (`flotte-web-team.yaml`) :
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: flotte-web-team
     namespace: flotte-apps
   spec:
     project: flotte
     source:
       repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
       targetRevision: main
       path: apps/flotte-web
     destination:
       server: https://kubernetes.default.svc
       namespace: flotte-team
     syncPolicy:
       automated: {}
       syncOptions: [CreateNamespace=true]
   ```
   `kubectl apply -f flotte-web-team.yaml` → condition mesurée :
   ```
   application 'flotte-web-team' in namespace 'flotte-apps' is not permitted to use project 'flotte'
   ```
3. Autorisation dans le projet :
   ```bash
   kubectl patch appproj flotte -n argocd --type merge -p '{"spec":{"sourceNamespaces":["flotte-apps"]}}'
   ```
   Résultat : `Synced` / `Healthy` en moins d'une minute ; `argocd app list` → `flotte-apps/flotte-web-team`.
4. Même Application dans `flotte-dev` : objet créé, aucun statut (`.status` vide), aucune ressource déployée.
5. RBAC (mesuré avec `rbac can --policy-file`) :

   | Règle | Objet `flotte/flotte-apps/flotte-web-team` | Objet `flotte/flotte-web` |
   |---|---|---|
   | `p, role:dev, applications, sync, flotte/*, allow` | Yes | Yes |
   | `p, role:dev, applications, sync, flotte/flotte-apps/*, allow` | Yes | No |
6. Nettoyage :
   ```bash
   kubectl delete -f flotte-web-team.yaml
   kubectl delete namespace flotte-apps flotte-team
   kubectl patch cm argocd-cmd-params-cm -n argocd --type json -p '[{"op":"remove","path":"/data/application.namespaces"}]'
   kubectl patch appproj flotte -n argocd --type json -p '[{"op":"remove","path":"/spec/sourceNamespaces"}]'
   kubectl rollout restart deploy/argocd-server -n argocd
   kubectl rollout restart sts/argocd-application-controller -n argocd
   ```

### Pourquoi
- Double verrou : `application.namespaces` (namespaces observés par le serveur et le contrôleur) + `sourceNamespaces` (projets utilisables depuis ce namespace). Sans le second, une équipe pourrait se rattacher à n'importe quel projet.
- Namespace non déclaré : Application invisible pour ArgoCD, sans erreur → piège de diagnostic.
- Nom qualifié `<NS>/<APP>` dans la CLI et objet RBAC `<PROJET>/<NS>/<APP>` ; le glob `*` couvre aussi `/` : `flotte/*` donne accès aux Applications de tous les namespaces rattachées à `flotte`.
- Intérêt : délégation par le RBAC Kubernetes (droit `create applications` dans `flotte-apps` seulement), aucun accès au namespace `argocd`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Aucun statut même après `sourceNamespaces` | Composants non redémarrés après la modification de `argocd-cmd-params-cm` | `rollout restart` du serveur et du contrôleur |
| `resource :Namespace is not permitted in project flotte` | `Namespace` absent de `clusterResourceWhitelist` | Whitelist du Lab 03.4, ou namespace créé à la main |
| `argocd app get flotte-web-team` → `not found` | Nom non qualifié | `argocd app get flotte-apps/flotte-web-team` |

## Défi 04.6 ⭐⭐⭐ — `flotte-web` en Jsonnet paramétré
Testé sur un cluster kind séparé (ArgoCD 3.6.1).

### Solution
`jsonnet/flotte-web/lib.libsonnet` :
```jsonnet
{
  deployment(name, env, replicas, image):: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: { name: name, labels: { app: name, env: env } },
    spec: {
      replicas: replicas,
      selector: { matchLabels: { app: name } },
      template: {
        metadata: { labels: { app: name, env: env } },
        spec: { containers: [{ name: 'web', image: image,
          env: [{ name: 'PODINFO_UI_MESSAGE', value: 'Hexa Mobilite - ' + env }] }] },
      },
    },
  },
  service(name):: {
    apiVersion: 'v1', kind: 'Service',
    metadata: { name: name },
    spec: { selector: { app: name }, ports: [{ port: 80, targetPort: 9898 }] },
  },
}
```
`jsonnet/flotte-web/main.jsonnet` :
```jsonnet
local lib = import 'lib.libsonnet';
function(env='dev', replicas=1, tag='6.16.0')
  local name = 'flotte-web-' + env;
  [
    lib.deployment(name, env, replicas, 'ghcr.io/stefanprodan/podinfo:' + tag),
    lib.service(name),
  ]
```
Application (extrait `source`) :
```yaml
  source:
    repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
    targetRevision: main
    path: jsonnet/flotte-web
    directory:
      include: main.jsonnet
      jsonnet:
        tlas:
          - {name: env, value: recette}
          - {name: replicas, value: "2", code: true}
  destination: {server: https://kubernetes.default.svc, namespace: flotte-recette}
  syncPolicy: {automated: {}, syncOptions: [CreateNamespace=true]}
```
Résultat mesuré : `Synced` / `Healthy`, `deployment.apps/flotte-web-recette 2/2`, `service/flotte-web-recette`.

Sans `code: true` → échec mesuré :
```
error when patching "...": "" is invalid: patch: Invalid value: "": unrecognized type: int32
```

### Pourquoi
- `tlas` (*top-level arguments*) : paramètres de la fonction principale, déclarés dans l'Application → un même code pour tous les environnements, comme `valuesObject` en Helm.
- `value` seul = chaîne (`--tla-str`) ; `code: true` = expression Jsonnet (`--tla-code`) → nombre `2` et non chaîne `"2"`.
- `.libsonnet` ignoré par le rendu ; `include: main.jsonnet` rend l'intention explicite (seul ce fichier est évalué).
- `extVars` : alternative (variables globales `std.extVar`), moins lisible qu'une fonction typée.
- Comparatif pour l'équipe : Jsonnet = vrai langage (fonctions, imports), sans gestion de version de paquet comme Helm.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `RUNTIME ERROR: function has no parameter envs` | Nom de TLA différent du paramètre | Aligner `name` sur la signature |
| `Expected a comma before next field` | Virgule manquante entre champs | `jsonnet main.jsonnet` en local |
| Rendu vide | Fichier renvoyant un objet au lieu d'une liste ou d'un objet Kubernetes | Renvoyer `[ ... ]` |

## Bonus
- Sans `recurse` : la ConfigMap `flotte-extra` du sous-dossier est ignorée ; l'application reste `Synced` (testé).
- Avec `source.directory.recurse: true` : `OutOfSync`, ressource `flotte-extra` `Missing` jusqu'à la synchronisation (testé).
- Un fichier `.yaml` sans `apiVersion` / `kind` dans le dossier est ignoré par ArgoCD 3.6 (testé) ; un fichier `.md` également.
- Règle à retenir : un dossier par application, sous-dossiers explicitement inclus (`recurse`) ou exclus (`exclude`).

## QCM — Réponses
1. **B** — L'Application est une ressource ArgoCD du namespace `argocd` ; `flotte-dev` est sa destination.
2. **B** — Ressources absentes du cluster : `OutOfSync` (écart avec Git) et `Missing` (santé).
3. **C** — Une branche est réévaluée à chaque réconciliation ; tag et commit figent la révision.
4. **A** — Le `repo-server` détecte Helm à la présence de `Chart.yaml`.
5. **B** — Le finalizer déclenche la suppression en cascade des ressources gérées.
6. **B** — `latest` : nouvelle image sans modification de Git, donc ni écart détecté ni historique.
7. **A** — `argocd app manifests <APP> --source git` affiche le rendu des manifestes depuis Git.
