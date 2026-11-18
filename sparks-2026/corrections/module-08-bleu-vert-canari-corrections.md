# Module 08 — Corrections

Script d'état final du module (testé sur v3.6.1 + Argo Rollouts v1.10.2) — mêmes variables que le M04 :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m08/catch-up/m08-final-state.sh
```
État obtenu : Argo Rollouts installé ; `flotte-web` (dev) en Rollout canari ; `flotte-web-recette` (bleu-vert) créée ; les deux applications `Synced` / `Healthy`. Prérequis : plugin `kubectl-argo-rollouts` installé.

## Lab 08.1 ⭐ — Installer Argo Rollouts
### Solution
Commandes de l'énoncé ; script équivalent : `scripts/m08/labs/install-rollouts.sh`. CRD (testé) :
```
analysisruns.argoproj.io               2026-11-08T13:32:27Z
analysistemplates.argoproj.io          2026-11-08T13:32:06Z
clusteranalysistemplates.argoproj.io   2026-11-08T13:32:07Z
experiments.argoproj.io                2026-11-08T13:32:07Z
rollouts.argoproj.io                   2026-11-08T13:32:31Z
```

### Pourquoi
- Contrôleur installé hors ArgoCD par l'équipe ops : CRD et ressources de niveau cluster, non autorisées dans le projet `flotte` (seul `Namespace` l'est). En production : Application dédiée dans un projet plateforme.
- `--server-side` : CRD `rollouts` et `analysisruns` refusées sinon (`metadata.annotations: Too long: may not be more than 262144 bytes`, testé).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `metadata.annotations: Too long` | Apply client | Relancer avec `--server-side --force-conflicts` |
| `error: unknown command "argo" for "kubectl"` | Plugin absent du `PATH` ou mal nommé | Nom exact `kubectl-argo-rollouts`, dossier du `PATH` |
| Pod `argo-rollouts` `ImagePullBackOff` | Réseau (`quay.io`) | `docker pull quay.io/argoproj/argo-rollouts:v1.10.2` + `kind load docker-image` |

## Lab 08.2 ⭐ — Livraison canari pilotée depuis ArgoCD
### Solution
`labs/m08/rollout-canary.yaml` : modèle de pod identique au Deployment du M07, plus :
```yaml
spec:
  replicas: 4
  progressDeadlineSeconds: 60
  revisionHistoryLimit: 3
  strategy:
    canary:
      steps:
        - setWeight: 25
        - pause: {duration: 30s}
        - setWeight: 50
        - pause: {}
        - setWeight: 100
```
Observations (testées) :
```
Status:          ॥ Paused
Message:         CanaryPauseStep
Strategy:        Canary
  Step:          1/5
  SetWeight:     25
  ActualWeight:  25
Images:          ghcr.io/stefanprodan/podinfo:6.16.0 (stable)
                 ghcr.io/stefanprodan/podinfo:6.17.0 (canary)
```
Pendant la pause : opération ArgoCD `Running | waiting for healthy state of argoproj.io/Rollout/flotte-web`. Après `resume` : `✔ Healthy`, `Step: 5/5`, image `6.17.0 (stable)`, smoke test `Succeeded`.

### Pourquoi
- 4 réplicas : poids de 25 % et 50 % réalisés exactement (1 et 2 pods) sans routeur de trafic.
- `pause: {duration: 30s}` : reprise automatique ; `pause: {}` : attente d'une action humaine.
- Le Rollout en pause est `Suspended` : la synchronisation ArgoCD attend un état sain, donc les hooks PostSync ne s'exécutent qu'après la promotion complète.
- Suppression du Deployment par prune (activé au M05) dans la même synchronisation que la création du Rollout ; en production, migration sans interruption par `workloadRef` (documentation Argo Rollouts, *Migrating*) : Rollout créé avec `workloadRef` vers le Deployment existant → ses pods démarrent à côté de ceux du Deployment (double capacité pendant la migration) → Deployment réduit selon `scaleDown` (`never`, `onsuccess` une fois le Rollout sain, `progressively` au fil de la montée) ou à la main (`replicas: 0`), puis supprimé.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Passage direct à 100 % | Premier déploiement du Rollout (aucune version stable) | Normal ; livrer une seconde version |
| `the server could not find the requested resource` | Contrôleur ou CRD absents | Lab 08.1 |
| Deployment et Rollout coexistent | Prune désactivé | `prune: true` (M05) ou suppression manuelle du Deployment |
| `permission denied` sur l'action | Contexte `alice` (pas de permission `action/...`) | Contexte administrateur |

## Exercice 08.3 ⭐⭐ — Interrompre un canari défaillant
### Solution
```bash
sed -i -E 's#(podinfo:)[0-9.]+#\16.99.0#' apps/flotte-web/rollout.yaml
git commit -am "feat: 6.99.0" && git push && argocd app get flotte-web-dev --refresh > /dev/null
# après environ 60 s
kubectl argo rollouts get rollout flotte-web -n flotte-dev | head -8
argocd app actions run flotte-web-dev abort --kind Rollout --resource-name flotte-web
argocd app terminate-op flotte-web-dev
git revert --no-edit HEAD && git push && argocd app get flotte-web-dev --refresh > /dev/null
```
Observations (testées) :
```
Status:          ✖ Degraded
Message:         ProgressDeadlineExceeded: ReplicaSet "flotte-web-686c567b76" has timed out progressing.
```
Après `abort` :
```
Message:         RolloutAborted: Rollout aborted update to revision 3
  SetWeight:     0
Images:          ghcr.io/stefanprodan/podinfo:6.17.0 (stable)
```
Après revert : `Synced` / `Healthy`.

RBAC : `dev-alice` reçoit `permission denied` (testé). Règle proposée :
```text
p, role:dev, applications, action/argoproj.io/Rollout/resume, flotte/*, allow
```

### Pourquoi
- `abort` agit sur le cluster, pas sur Git : la spécification demandée (`6.99.0`) reste dans Git, d'où `Degraded` jusqu'au revert (même logique que le rollback d'urgence du M06).
- Le service n'a jamais été interrompu : les 4 pods stables restent en place pendant tout l'incident.

## Exercice 08.4 ⭐⭐ — Bleu-vert en recette
### Solution
Fichiers : `labs/m08/flotte-web-recette/{configmap,rollout-bluegreen,services}.yaml`, Application `labs/m08/flotte-web-recette-app.yaml` (`path: apps/flotte-web-recette`, destination `flotte-recette`, synchronisation automatique).
```bash
kubectl apply -f argocd/flotte-web-recette.yaml
# livraison 6.17.0 dans apps/flotte-web-recette/rollout-bluegreen.yaml, push, refresh
kubectl port-forward -n flotte-recette svc/flotte-web 9901:80 &
kubectl port-forward -n flotte-recette svc/flotte-web-preview 9902:80 &
curl -s localhost:9901 | grep '"version"'; curl -s localhost:9902 | grep '"version"'
argocd app actions run flotte-web-recette promote-full --kind Rollout --resource-name flotte-web
```
Observations (testées, pendant la pause d'une livraison de `6.15.0` après `6.17.0`) :
```
active:   "version": "6.17.0",
preview:   "version": "6.15.0",
NAME                 SELECTOR
flotte-web           map[app.kubernetes.io/name:flotte-web rollouts-pod-template-hash:6d58dcbb64]
flotte-web-preview   map[app.kubernetes.io/name:flotte-web rollouts-pod-template-hash:69b7f8b8cd]
```
Après promotion : le service actif sert la nouvelle version ; application `Healthy`.

### Pourquoi
- `autoPromotionEnabled: false` : bascule seulement sur décision (`promote-full`, *Resume* dans l'UI ou `kubectl argo rollouts promote`).
- Sélecteur enrichi par Argo Rollouts : chaque service vise exactement un ReplicaSet ; ArgoCD reste `Synced` (champ géré par le contrôleur).
- `scaleDownDelaySeconds: 30` : l'ancienne version reste disponible 30 s après la bascule (retour quasi immédiat possible).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Les deux services renvoient la même version | Pas de livraison en cours (pause terminée) | Livrer une nouvelle version, interroger pendant la pause |
| `Service "flotte-web-preview" not found` dans le Rollout | Fichier `services.yaml` absent | Copier les 3 fichiers |
| Application recette refusée | `<GITLAB_USER>` non remplacé | `sed` sur le modèle |

## Défi 08.5 ⭐⭐⭐ — Analyse automatique du canari
### Solution
Extrait de `rollout.yaml` :
```yaml
  strategy:
    canary:
      canaryService: flotte-web-canary
      steps:
        - setWeight: 25
        - analysis:
            templates:
              - templateName: flotte-smoke
        - setWeight: 50
        - pause: {}
        - setWeight: 100
```
`labs/m08/analysis-template.yaml` : métrique `readyz`, 3 mesures espacées de 10 s, 1 échec toléré, Job `curl -fsS http://flotte-web-canary/readyz`.

Résultats (testés) :
```
NAME                        STATUS       AGE
flotte-web-58bd86d49d-6-1   Failed       55s
flotte-web-84ff865457-5-1   Successful   2m36s
```
```
RolloutAborted: Rollout aborted update to revision 6: Step-based analysis phase error/failed: Metric "readyz" assessed Failed due to failed (2) > failureLimit (1)
```

### Pourquoi
- `canaryService` : Argo Rollouts restreint ce service aux seuls pods canari ; l'analyse mesure la nouvelle version, pas le mélange.
- Interruption automatique : aucune intervention humaine, version stable conservée.
- En production : fournisseur Prometheus (taux d'erreur, latence du canari) plutôt qu'un Job.

## Défi 08.6 ⭐⭐⭐ — Migrer un Deployment existant vers un Rollout sans coupure
Testé sur un cluster kind séparé (ArgoCD 3.6.1, Argo Rollouts v1.10.2).

### Solution
État initial (`apps/flotte-web-mig/deployment.yaml` et `service.yaml`) : Deployment `flotte-web` 3 réplicas, Service `flotte-web` (sélecteur `app: flotte-web`).

Sonde :
```bash
kubectl run sonde -n flotte-mig --image=curlimages/curl:8.17.0 --restart=Never --command -- \
  sh -c 'while true; do if curl -fs --max-time 2 http://flotte-web/readyz >/dev/null; then echo OK; else echo KO $(date +%T); fi; sleep 1; done'
```
Rollout ajouté (`apps/flotte-web-mig/rollout.yaml`) :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: flotte-web
spec:
  replicas: 3
  selector:
    matchLabels: {app: flotte-web}
  workloadRef:
    apiVersion: apps/v1
    kind: Deployment
    name: flotte-web
    scaleDown: progressively
  strategy:
    canary:
      steps:
        - setWeight: 100
```
Observation mesurée après le push :

| Moment | Deployment | Rollout | Application |
|---|---|---|---|
| +60 s | `0/0` | 3/3 | `OutOfSync` / `Healthy` |
| +2 min | `0` (remis à 3 par le self-heal puis réduit par Rollouts) | 3/3 | `OutOfSync`, nouvelle opération de synchronisation terminée |

`argocd app diff flotte-web-mig` :
```
===== apps/Deployment flotte-mig/flotte-web ======
<   replicas: 0
---
>   replicas: 3
```
Résolution : `replicas: 0` dans `deployment.yaml` de Git → `Synced` / `Healthy`. Sonde : `KO total: 0 / OK 154`.

### Pourquoi
- `workloadRef` : le Rollout réutilise le gabarit de pod du Deployment → même libellé, le Service sert ancien et nouveaux pods pendant la transition.
- `scaleDown: progressively` : l'ancien Deployment est réduit au rythme où les pods du Rollout deviennent disponibles (`never` = laissé tel quel, `onsuccess` = réduit après succès).
- Conflit : Git dit `replicas: 3`, le contrôleur Rollouts écrit `0` ; le self-heal réapplique 3 → boucle (pods créés puis supprimés, opérations répétées). Git doit décrire l'état voulu après migration : `replicas: 0` (alternative : `ignoreDifferences` sur `/spec/replicas` du Deployment).
- Étape suivante habituelle : déplacer le gabarit dans le Rollout (`spec.template`), puis supprimer le Deployment.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Rollout `Degraded` : `workload not found` | Nom ou `apiVersion` de `workloadRef` erronés | `apps/v1`, `Deployment`, nom exact |
| Pods en double durablement (6 au lieu de 3) | `scaleDown: never` | `progressively`, ou `replicas: 0` dans Git |
| Coupure pendant la migration | Sélecteur du Rollout différent de celui du Deployment | Reprendre exactement `selector.matchLabels` |

## Défi 08.7 ⭐⭐⭐ — Bleu-vert : analyse de la preview avant bascule
Testé sur un cluster kind séparé (ArgoCD 3.6.1, Argo Rollouts v1.10.2), fichiers de `labs/m08/flotte-web-recette/`.

### Solution
`apps/flotte-web-recette/analysis-preview.yaml` :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: flotte-preview-check
spec:
  args:
    - name: chemin
      value: /readyz
  metrics:
    - name: preview
      count: 3
      interval: 5s
      failureLimit: 0
      provider:
        job:
          spec:
            backoffLimit: 0
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: check
                    image: curlimages/curl:8.17.0
                    command: ["curl", "-fsS", "--max-time", "5", "http://flotte-web-preview{{args.chemin}}"]
```
Stratégie du Rollout :
```yaml
  strategy:
    blueGreen:
      activeService: flotte-web
      previewService: flotte-web-preview
      autoPromotionSeconds: 20
      prePromotionAnalysis:
        templates:
          - templateName: flotte-preview-check
      scaleDownDelaySeconds: 30
```
Chronologie mesurée (`6.16.0` → `6.17.0`) :
```
17:04:26 Progressing active service cutover pending | AnalysisRun Running    | actif=759c86897f
17:04:46 Paused BlueGreenPause                     | AnalysisRun Successful | actif=759c86897f
17:05:07 Healthy                                   | AnalysisRun Successful | actif=6d58dcbb64
```
Version défaillante (`6.15.0`), ajout sous `templates` :
```yaml
        args:
          - name: chemin
            value: /status/500
```
Résultat mesuré :
```
Degraded | RolloutAborted: Rollout aborted update to revision 3: Blue/green pre-promotion analysis phase
error/failed: Metric "preview" assessed Failed due to failed (1) > failureLimit (0)
```
Service actif inchangé (`6d58dcbb64`), Application `Synced` / `Degraded`. `git revert HEAD && git push` → Rollout `Healthy`, `6.17.0` (`stable`, `active`).

### Pourquoi
- `prePromotionAnalysis` : vérification exécutée contre la preview, avant toute bascule ; échec → abandon, le trafic n'a jamais atteint la nouvelle version.
- `autoPromotionSeconds` : promotion automatique après le délai, seulement si l'analyse a réussi.
- `args` : un seul modèle, réutilisable par plusieurs Rollouts ou environnements ; valeur par défaut dans le modèle, surcharge dans le Rollout.
- Application `Degraded` après abandon : santé du Rollout reprise par ArgoCD → notifications du M07 déclenchées.
- Retour par `git revert` : Git redevient égal à la version stable, le Rollout se réaligne sans nouvelle analyse.
- `postPromotionAnalysis` : variante après bascule, avec retour arrière automatique si elle échoue.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `AnalysisRun` `Error` immédiat | Image `curl` non téléchargeable, ou `args` sans valeur | `kubectl describe analysisrun` ; valeur par défaut dans le modèle |
| Analyse réussie sur une version défaillante | URL vers `flotte-web` (actif) au lieu de `flotte-web-preview` | Viser le service preview |
| Rollout resté `Degraded` | Correction par `kubectl argo rollouts` au lieu de Git, puis resynchronisation | Corriger dans Git (`git revert`) |

## Bonus
Tableau de bord local : `kubectl argo rollouts dashboard` (port 3100 par défaut, `--port` pour le changer). Vue détaillée des étapes, des ReplicaSets et des analyses ; boutons *Promote* et *Abort* équivalents aux actions ArgoCD (actions hors ArgoCD : non tracées dans l'historique de l'application).

## QCM — Réponses
1. **B** — Le canari augmente progressivement la part de la nouvelle version.
2. **C** — Un Rollout en pause est évalué `Suspended` par ArgoCD.
3. **B** — `abort` ramène le canari à 0 % ; la version stable continue de servir.
4. **B** — Sans routeur de trafic, le poids est la proportion de pods : 1 sur 4.
5. **B** — Le service actif reste sur l'ancienne version jusqu'à la promotion.
6. **B** — Certaines CRD dépassent 262 144 octets d'annotation `last-applied`.
7. **B** — Les actions de ressource sont autorisées par `action/<groupe>/<type>/<action>`.
