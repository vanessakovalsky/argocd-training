# Module 09 — Corrections

Script d'état final du module (testé sur v3.6.1) — mêmes variables que le M04 :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m09/catch-up/m09-final-state.sh
```
État obtenu : `flotte-web` en base + overlays Kustomize, `flotte-web-dev` et `flotte-web-recette` sur leurs overlays, `flotte-api-dev` (chart Helm, valeurs dans Git) ; trois Applications `Synced` / `Healthy`. Le Défi 09.5 (production) n'est pas inclus.

## Lab 09.1 ⭐ — Chart Helm avec valeurs dans Git
### Solution
`labs/m09/argocd/flotte-api-dev.yaml` :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-api-dev
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: flotte
  sources:
    - repoURL: https://stefanprodan.github.io/podinfo
      chart: podinfo
      targetRevision: 6.17.0
      helm:
        releaseName: flotte-api
        valueFiles:
          - $values/helm/flotte-api/values-common.yaml
          - $values/helm/flotte-api/values-dev.yaml
    - repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: flotte-dev
  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
```
Résultat (testé) :
```
Sources:
- Repo:             https://stefanprodan.github.io/podinfo
  Target:           6.17.0
  Helm Values:      $values/helm/flotte-api/values-common.yaml,$values/helm/flotte-api/values-dev.yaml
- Repo:             <URL_FLOTTE_CONFIG>
  Target:           main
  Ref:              values
Sync Status:        Synced to 6.17.0
Health Status:      Healthy
```

### Pourquoi
- Source `ref: values` : ne déploie rien elle-même, elle rend ses fichiers accessibles sous `$values/` aux autres sources.
- Fichier commun + fichier par environnement : `values-dev.yaml` ne contient que les écarts (1 réplica, couleur verte).
- Ressources nommées `flotte-api-podinfo` : `releaseName` + nom du chart (convention du chart podinfo).
- Révision affichée = version du chart (`6.17.0`) ; un commit dans `helm/flotte-api/` déclenche aussi une nouvelle synchronisation.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `application repo https://stefanprodan.github.io/podinfo is not permitted` | Source absente du projet | `argocd proj add-source` |
| `open <CHEMIN>/helm/flotte-api/values-dev.yaml: no such file` | Fichier non poussé ou chemin faux après `$values/` | `git push` ; chemin relatif à la racine du dépôt |
| Valeurs ignorées | `ref` différent de `values` dans la seconde source | `ref: values` et `$values/` identiques |
| `helm template` local différent du rendu ArgoCD | Version du chart différente (`--version` oublié) | Toujours `--version 6.17.0` |

## Exercice 09.2 ⭐⭐ — Priorité des valeurs Helm
### Solution
```bash
argocd app set flotte-api-dev --source-position 1 --helm-set replicaCount=2
argocd app manifests flotte-api-dev | grep -m1 replicas:
argocd app unset flotte-api-dev --source-position 1 --parameter replicaCount
```
Résultats (testés) : `replicas: 2` avec le paramètre ; avec `parameters: 2` et `valuesObject: {replicaCount: 3}` : `replicas: 2` ; avec `valuesObject` seul : `replicas: 3` ; état versionné : `replicas: 1`.

### Pourquoi
- Ordre documenté et vérifié : `parameters > valuesObject > values > valueFiles > values.yaml du chart`.
- `--source-position 1` : obligatoire sur une Application multi-sources (numérotation à partir de 1).
- Risques d'une surcharge par la CLI : invisible dans Git, perdue à la prochaine application du fichier `argocd/flotte-api-dev.yaml`, non revue ; acceptable pour une urgence, à reporter ensuite dans `values-dev.yaml`.

## Lab 09.3 ⭐⭐ — `flotte-web` en base et overlays Kustomize
### Solution
Structure finale (`labs/m09/apps/flotte-web/`) :
```
base/
  kustomization.yaml          # configurations, resources, configMapGenerator, images
  rollout-transform.yaml      # fourni par Argo Rollouts v1.10.2 (Kustomize 5)
  rollout.yaml                # canari + analyse (M08)
  service.yaml  service-canary.yaml  analysis-template.yaml
  hook-presync-migration.yaml  hook-postsync-smoke-test.yaml
overlays/
  dev/kustomization.yaml      # image 6.17.0, message DEV
  recette/kustomization.yaml  # patch bleu-vert, 2 réplicas, message RECETTE
  recette/service-preview.yaml
  prod/kustomization.yaml     # 4 réplicas, message de production
```
Rendu (testé) :
```
== dev      image 6.17.0, canary, replicas 4, flotte-web-config-4c48ggb2h2
== recette  image 6.16.0, blueGreen, replicas 2, flotte-web-config-8dthm9kbf5
== prod     image 6.16.0, canary, replicas 4, flotte-web-config-54dbm56c57
```
Au changement de chemin, l'ancienne ConfigMap `flotte-web-config` (non hachée) est supprimée (`Pruned`) et la ConfigMap hachée créée ; les livraisons passent par le canari (dev) et le bleu-vert (recette).

### Pourquoi
- Une seule description de `flotte-web` ; chaque environnement n'écrit que ses écarts.
- `configurations: [rollout-transform.yaml]` : sans ce fichier, Kustomize ne connaît pas la structure d'un Rollout ; la référence `configMapRef` resterait `flotte-web-config` (ConfigMap inexistante).
- Patch JSON pour la stratégie : remplacement complet de `/spec/strategy` (une fusion laisserait `canary` ET `blueGreen`, configuration refusée).
- `images` : tag de l'image modifié sans toucher au YAML de la base.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Pods `CreateContainerConfigError` : `configmap "flotte-web-config" not found` | `rollout-transform.yaml` absent de `configurations` | Ajouter le fichier et la ligne `configurations` |
| `accumulating resources` sur le chemin `../../base` | Mauvais niveau de dossier | Overlays dans `overlays/<env>/`, base dans `base/` |
| Rollout recette refusé (deux stratégies) | Patch stratégique au lieu d'un `replace` JSON | Patch JSON `op: replace` |
| Application recette `OutOfSync` permanent | Service `flotte-web-preview` absent de l'overlay | `resources: [../../base, service-preview.yaml]` |

## Exercice 09.4 ⭐⭐ — Changer la configuration sans oublier les pods
### Solution
Après modification du message de `dev` (testé) :
```
NAME                           DATA   AGE
flotte-web-config-4c48ggb2h2   2      3m19s
flotte-web-config-fckt6km9b8   2      54s
ConfigMap  flotte-dev  flotte-web-config-4c48ggb2h2  OutOfSync  ignored (no prune)
ConfigMap  flotte-dev  flotte-web-config-fckt6km9b8  Synced     configmap/flotte-web-config-fckt6km9b8 created
```
Application `Synced` / `Healthy` ; message servi : `Hexa Mobilite - DEV v2` (après promotion du canari).

Annotations du générateur :
- `argocd.argoproj.io/sync-wave: "-1"` : ConfigMap créée avant le Rollout qui la référence.
- `argocd.argoproj.io/sync-options: Prune=false` : l'ancienne ConfigMap reste disponible pour la version stable (canari en cours, `abort`, rollback).
- `argocd.argoproj.io/compare-options: IgnoreExtraneous` : l'ancienne ConfigMap ne rend pas l'application `OutOfSync` (recommandation de la documentation ArgoCD pour les générateurs Kustomize).

## Défi 09.5 ⭐⭐⭐ — Environnement de production
### Solution
`labs/m09/argocd/flotte-web-prod.yaml` :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-web-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: flotte
  source:
    repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
    targetRevision: v1.0.0
    path: apps/flotte-web/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: flotte-prod
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```
```bash
git tag v1.0.0 && git push origin v1.0.0
kubectl apply -f argocd/flotte-web-prod.yaml
argocd app sync flotte-web-prod && argocd app wait flotte-web-prod --health
```
Résultat (testé) : `Synced to v1.0.0`, Rollout à 4 réplicas, image `6.16.0`.

Promotion : `git tag v1.1.0 && git push origin v1.1.0`, puis `targetRevision: v1.1.0` dans le fichier (commit, revue), `kubectl apply`, `argocd app sync`.

Comparaison : `dev` suit `main` et se synchronise seul à chaque commit ; `prod` suit un tag figé et ne change que par une décision explicite (changement de tag + synchronisation manuelle).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `unable to resolve 'v1.0.0' to a commit SHA` | Tag non poussé | `git push origin v1.0.0` |
| Namespace `flotte-prod` refusé | Hors du motif `flotte-*` | Respecter le préfixe `flotte-` |
| Production modifiée par un commit sur `main` | `targetRevision: main` laissé | Tag explicite |

## Défi 09.6 ⭐⭐⭐ — Composants Kustomize et remplacements
Testé avec `kubectl kustomize` (kubectl v1.36.6) et ArgoCD 3.6.1 sur un cluster kind séparé (Argo Rollouts v1.10.2), à partir des fichiers de `labs/m09/apps/flotte-web/`.

### Solution
`components/hpa/kustomization.yaml` :
```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - hpa.yaml
patches:
  - target: {kind: Rollout, name: flotte-web}
    patch: |-
      - op: remove
        path: /spec/replicas
```
`components/hpa/hpa.yaml` :
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: flotte-web
spec:
  scaleTargetRef: {apiVersion: argoproj.io/v1alpha1, kind: Rollout, name: flotte-web}
  minReplicas: 3
  maxReplicas: 8
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
```
`components/debug/kustomization.yaml` :
```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
configMapGenerator:
  - name: flotte-web-config
    behavior: merge
    literals:
      - PODINFO_LEVEL=debug
```
`overlays/prod/kustomization.yaml` (bloc `replicas` du Lab 09.3 **supprimé**) :
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
configMapGenerator:
  - name: flotte-web-config
    behavior: merge
    literals:
      - PODINFO_UI_MESSAGE=Hexa Mobilite
      - ENVIRONNEMENT=prod
components:
  - ../../components/hpa
replacements:
  - source:
      kind: ConfigMap
      name: flotte-web-config
      fieldPath: data.ENVIRONNEMENT
    targets:
      - select: {kind: Rollout, name: flotte-web}
        fieldPaths:
          - spec.template.metadata.labels.hexa-mobilite/environnement
        options: {create: true}
```
`overlays/dev/kustomization.yaml` : ajouter `components: [../../components/debug]`.

Rendus mesurés :

| Cas | `replicas` du Rollout | HPA | Libellé |
|---|---|---|---|
| `prod` avec le bloc `replicas: count: 4` conservé | `4` (réintroduit) | `minReplicas: 3` | `prod` |
| `prod` sans le bloc | absent | `minReplicas: 3` | `prod` |
| `dev` | inchangé | absent | — (`PODINFO_LEVEL: debug`) |

Synchronisation ArgoCD de `prod` : `Synced`, Rollout 3/3 (fixé par le HPA), Application `Degraded` :
```
HorizontalPodAutoscaler  Degraded  the HPA was unable to compute the replica count: failed to get cpu utilization:
unable to get metrics for resource cpu: ... (get pods.metrics.k8s.io)
```

### Pourquoi
- Composant = morceau d'overlay réutilisable et optionnel ; inclus par `components`, il s'applique après `resources` et avant les transformations propres à l'overlay (`replicas`, `images`, générateurs de l'overlay) → le bloc `replicas` de l'overlay réécrit le champ supprimé par le composant.
- Retirer `spec.replicas` quand un HPA pilote la cible : sinon chaque synchronisation remet la valeur de Git et l'HPA la corrige (conflit, comme au Défi 08.6).
- `replacements` (remplace les `vars` dépréciées) : une valeur source, plusieurs cibles ; `options.create` crée le champ absent ; référence au nom d'origine de la ConfigMap, même hachée.
- `Degraded` : kind n'a pas de metrics-server, l'HPA ne peut pas calculer → santé ArgoCD fidèle à la réalité. Solution : installer metrics-server (en kind : option `--kubelet-insecure-tls`) ou accepter l'état en laboratoire.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `list path element must contain fieldName=fieldValue` | Chemin écrit `labels.[hexa-mobilite/environnement]` | `labels.hexa-mobilite/environnement` (crochets réservés aux sélecteurs de liste) |
| `apiVersion for Component should be kustomize.config.k8s.io/v1alpha1` | `v1beta1` recopié depuis une Kustomization | `kustomize.config.k8s.io/v1alpha1` |
| `PODINFO_LEVEL` absent en `dev` | Composant listé mais générateur sans `behavior: merge` | `behavior: merge` |

## Défi 09.7 ⭐⭐⭐ — Chart Helm OCI et contrainte de version
Testé sur un cluster kind séparé (ArgoCD 3.6.1).

### Solution
```bash
argocd repo add ghcr.io/stefanprodan/charts --type helm --enable-oci --name podinfo-oci
argocd proj add-source flotte ghcr.io/stefanprodan/charts
```
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-web-oci
  namespace: argocd
spec:
  project: flotte
  source:
    repoURL: ghcr.io/stefanprodan/charts
    chart: podinfo
    targetRevision: "~6.15.0"
    helm:
      releaseName: flotte-web
      valuesObject: {replicaCount: 1}
  destination: {server: https://kubernetes.default.svc, namespace: flotte-oci}
  syncPolicy:
    automated: {}
    syncOptions: [CreateNamespace=true]
```
Résolutions mesurées (`.status.sync.revision`) :

| `targetRevision` | Version résolue |
|---|---|
| `6.*` | `6.17.0` |
| `>=6.15.0 <6.17.0` | `6.16.0` |
| `~6.15.0` | `6.15.0` (correctifs `6.15.x` seulement) |

### Pourquoi
- `~6.15.0` = `>=6.15.0 <6.16.0` : correctifs automatiques, aucune nouvelle fonctionnalité ; `^6.15.0` = `<7.0.0` (mineures incluses) ; `6.*` = toute version 6, y compris une mineure qui change les valeurs par défaut du chart.
- Résolution à chaque rafraîchissement : une nouvelle version publiée est déployée sans commit → traçabilité par l'historique ArgoCD (révision = version résolue), pas par Git. Pour la production : version exacte, mise à jour par merge request (Renovate, Dependabot).
- OCI : `repoURL` = registre sans `oci://`, `chart` = nom du dépôt d'images ; authentification et proxy communs avec les images de conteneurs.
- Chart Git : révision = SHA de commit ; chart OCI : révision = version (tag) du chart.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Condition `InvalidSpecError` : dépôt non autorisé par le projet | Registre absent de `sourceRepos` | `argocd proj add-source` |
| `error loading repo index ... Get "ghcr.io/stefanprodan/charts/index.yaml": unsupported protocol scheme ""` | Dépôt déclaré sans `--enable-oci` | Recréer avec `--enable-oci` |
| Version inchangée après publication | Cache de résolution | `argocd app get <APP> --hard-refresh` |

## Bonus
`argocd-cm` : `kustomize.buildOptions: --enable-helm` (documentation ArgoCD : option non disponible par Application, réglage global ou plugin). Overlay de test :
```yaml
helmCharts:
  - name: podinfo
    repo: https://stefanprodan.github.io/podinfo
    version: 6.17.0
    releaseName: flotte-api
    valuesFile: values-dev.yaml
    skipTests: true      # écarte les Pods de test Helm du chart (3 Pods sinon)
```
Rendu testé avec les binaires du repo-server ArgoCD 3.6.1 (Helm v4.3.1, kustomize v5.8.3) : `kustomize build --enable-helm` → 1 Deployment + 1 Service ; sans l'option → `trouble configuring builtin HelmChartInflationGenerator`.

Comparaison attendue : Kustomize regroupe chart et patchs dans un même dossier ; l'Application multi-sources garde le chart hors du dépôt et ne modifie pas le comportement global d'ArgoCD. Piège sur le poste : kustomize v5.7 et plus ancien appelle `helm version -c`, option retirée de Helm 4 → `unknown shorthand flag: 'c'` ; tester le rendu avec `kubectl` v1.36 (kustomize v5.8) ou dans ArgoCD.

## QCM — Réponses
1. **B** — ArgoCD exécute l'équivalent de `helm template`, aucune release Helm n'est créée.
2. **C** — `parameters` a la priorité la plus haute.
3. **A** — `ref: values` expose le dépôt aux autres sources sous `$values/`.
4. **B** — Un overlay référence la base et décrit uniquement ses écarts.
5. **B** — L'empreinte du contenu change le nom, donc le modèle de pod, donc un nouveau déploiement.
6. **B** — `rollout-transform.yaml` décrit à Kustomize les chemins d'un Rollout (références, images, réplicas).
7. **B** — La version stable utilise encore l'ancienne ConfigMap pendant un canari ou après un retour arrière.
