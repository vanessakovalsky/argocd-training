# Module 07 — Corrections

Script d'état final du module (testé sur v3.6.1) — mêmes variables que le M04 :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m07/catch-up/m07-final-state.sh          # WITH_PROMETHEUS=1 pour le défi 07.5
```
État obtenu : `progressDeadlineSeconds: 60`, récepteur `alertes-receiver` dans `flotte-ops`, notifications `flotte-deployed` et `flotte-degraded` configurées et souscrites par `flotte-web-dev`.

## Lab 07.1 ⭐ — Préparer et parcourir les outils de diagnostic
### Solution
Commandes de l'énoncé. Extrait de `argocd app logs` (testé) :
```
{"level":"info","ts":"2026-11-08T13:02:37.003Z","caller":"http/server.go:289","msg":"Starting HTTP Server.","addr":":9898"}
```

### Pourquoi
- `progressDeadlineSeconds` (600 s par défaut dans Kubernetes) : délai au-delà duquel le Deployment est déclaré en échec de progression ; ArgoCD traduit cet état en `Degraded`.
- `app resources` : colonne `ORPHANED` = ressources présentes dans le namespace mais absentes de Git (projet `flotte` en `orphanedResources.warn`).
- `app logs` passe par l'API ArgoCD : pas besoin de droits Kubernetes, mais de la permission RBAC `logs, get`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `sed` sans effet | Ligne `replicas` différente (espaces, valeur) | Ajout manuel sous `spec:` |
| `app logs` : `permission denied` | Contexte d'un compte sans `logs, get` | `argocd context localhost:8443` |
| `app logs` affiche `waiting to start: ContainerCreating` | Pod d'un ReplicaSet en cours de remplacement | Relancer ; préciser `--name` d'un pod |

## Exercice 07.2 ⭐⭐ — Pannes injectées en binôme
### Solution
| Rubrique | Panne A : image inexistante | Panne B : `containerz` | Panne C : sonde `/pret` |
|---|---|---|---|
| Sync / Health | `Synced` / `Progressing` puis `Degraded` | `OutOfSync` / santé de la version précédente (`Healthy` si elle était saine) | `Synced` / `Progressing` puis `Degraded` |
| Ressource | Deployment `flotte-web` | Deployment `flotte-web` | Deployment `flotte-web` |
| Message | `Deployment "flotte-web" exceeded its progress deadline` ; événement `Failed to pull image "ghcr.io/stefanprodan/podinfo:6.99.0": rpc error: code = NotFound` | Opération : `Deployment.apps "flotte-web" is invalid: spec.template.spec.containers: Required value` | Événement `Readiness probe failed: HTTP probe failed with statuscode: 404` ; pod `0/1 Running` |
| Cause | Tag d'image inexistant | Faute de frappe : champ inconnu ignoré, champ requis absent | Chemin de sonde inexistant |
| Correction | `git revert` | `terminate-op` puis `git revert` | `git revert` |

Tous ces résultats ont été observés sur le banc de test (v3.6.1, `progressDeadlineSeconds: 60`).

Différence A / B : en A, l'API Kubernetes accepte le manifeste (synchronisation réussie, `Synced`), la panne survient à l'exécution ; en B, l'API refuse le manifeste (synchronisation en échec, `OutOfSync`), rien n'est modifié dans le cluster.

### Pourquoi
- Mise à jour progressive (`RollingUpdate`) : les anciens pods restent en service tant que les nouveaux ne sont pas prêts ; une panne de livraison n'interrompt pas le service.
- Panne B : nouvelles tentatives automatiques (5) ; `terminate-op` avant le revert évite d'attendre leur épuisement.
- Le hook PreSync de migration s'exécute à chaque tentative : visible dans l'arbre des ressources.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Panne A ou C restée `Progressing` | Lab 07.1 non fait (échéance de 600 s) | Attendre ou ajouter `progressDeadlineSeconds: 60` |
| Revert sans effet pendant la panne B | Opération en cours (tentatives) | `argocd app terminate-op flotte-web-dev` |
| Diagnostic par `kubectl edit` | Réflexe hors GitOps | Corriger dans Git ; self-heal annule les modifications manuelles |

## Lab 07.3 ⭐ — Notification webhook
### Solution
`labs/m07/argocd-notifications-cm-patch.yaml` :
```yaml
data:
  service.webhook.flotte-alertes: |
    url: http://alertes-receiver.flotte-ops.svc.cluster.local/argocd
    headers:
      - name: Content-Type
        value: application/json
  template.flotte-webhook: |
    webhook:
      flotte-alertes:
        method: POST
        body: |
          {"application": "{{.app.metadata.name}}",
           "sync": "{{.app.status.sync.status}}",
           "health": "{{.app.status.health.status}}",
           "revision": "{{.app.status.sync.revision}}"}
  trigger.flotte-deployed: |
    - when: app.status.operationState != nil and app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
      oncePer: app.status.sync.revision
      send: [flotte-webhook]
  trigger.flotte-degraded: |
    - when: app.status.health.status == 'Degraded'
      send: [flotte-webhook]
```
Annotations de l'Application (`labs/m07/flotte-web-dev-notif.yaml`) :
```yaml
metadata:
  annotations:
    notifications.argoproj.io/subscribe.flotte-deployed.flotte-alertes: ""
    notifications.argoproj.io/subscribe.flotte-degraded.flotte-alertes: ""
```
Réception (testée) :
```
    "path": "/argocd",
        "application": "flotte-web-dev",
        "sync": "Synced",
        "health": "Healthy",
        "revision": "c709618f8fa4a13ee25cfe62136cd00e96c599a2"
```

### Pourquoi
- Triggers nommés `flotte-*` : le catalogue officiel définit déjà `on-deployed` et `on-health-degraded` ; un nom identique écraserait l'un ou l'autre.
- `oncePer: app.status.sync.revision` : une seule notification par révision, même si la condition reste vraie.
- Première notification envoyée dès l'abonnement : la condition est vraie pour la révision déjà déployée.
- Destinataire vide (`""`) : le webhook n'a pas de destinataire variable (contrairement à un canal Slack).
- Abonnement dans le fichier de l'Application : versionné, il survit à une reconstruction.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Rien reçu, aucun `Sending notification` | Annotation mal formée (nom de trigger ou de service) | `kubectl get app flotte-web-dev -n argocd -o yaml \| grep subscribe` |
| Erreur de service inconnu dans les journaux du contrôleur de notifications | Clé `service.webhook.<nom>` absente ou mal nommée | Relire `argocd-notifications-cm` |
| `Sending notification` mais rien reçu | URL ou Service du récepteur faux | `kubectl get svc -n flotte-ops` |
| Erreur de template | JSON invalide (guillemets, accolades) | `kubectl logs deploy/argocd-notifications-controller -n argocd` |

## Exercice 07.4 ⭐⭐ — Lire les métriques
### Solution
```bash
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082 &
curl -s localhost:8082/metrics | grep -E '^argocd_app_info\{' | grep flotte-web-dev
curl -s localhost:8082/metrics | grep -E '^argocd_app_sync_total\{' | grep flotte-web-dev
```
Sorties observées (testées, valeurs variables) :
```
argocd_app_info{autosync_enabled="true",dest_namespace="flotte-dev",dest_server="https://kubernetes.default.svc",health_status="Healthy",hydrator_status="",name="flotte-web-dev",namespace="argocd",operation="",phase="Succeeded",project="flotte",repo="<URL_DEPOT>",sync_status="Synced"} 1
argocd_app_sync_total{dest_server="https://kubernetes.default.svc",dry_run="false",name="flotte-web-dev",namespace="argocd",phase="Failed",project="flotte"} 6
argocd_app_sync_total{dest_server="https://kubernetes.default.svc",dry_run="false",name="flotte-web-dev",namespace="argocd",phase="Succeeded",project="flotte"} 20
```
Labels d'alerte : `name`, `project`, `health_status`, `sync_status`, `autosync_enabled`, `dest_namespace`.

`argocd_app_health_status` (et `argocd_app_sync_status`, `argocd_app_created_time`) supprimées en 3.0 (notes de mise à jour 2.14 → 3.0) : l'information est portée par les labels de `argocd_app_info`.

### Pourquoi
- `argocd_app_info` vaut toujours 1 : c'est une métrique d'information, les états sont dans les labels.
- `argocd_app_sync_total` : compteur cumulatif ; utiliser `increase()` ou `rate()` sur une fenêtre.

## Défi 07.5 ⭐⭐⭐ — Prometheus et requêtes d'alerte
### Solution
```bash
kubectl apply -f labs/m07/prometheus-minimal.yaml
kubectl port-forward -n flotte-ops svc/prometheus 9090:9090
```
Cibles (testées) : `argocd-application-controller`, `argocd-repo-server`, `argocd-server` en `up`.

Requêtes :
```text
argocd_app_info{health_status="Degraded"}
argocd_app_info{sync_status="OutOfSync"}
sum by (name) (increase(argocd_app_sync_total{phase="Failed"}[1h]))
```
Règle d'alerte :
```yaml
groups:
  - name: argocd
    rules:
      - alert: ArgoCDApplicationDegraded
        expr: argocd_app_info{health_status="Degraded"} == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Application {{ $labels.name }} dégradée depuis 5 minutes"
```

### Pourquoi
- Prometheus minimal : configuration statique (`static_configs`) vers les Services ArgoCD ; en production, ServiceMonitor (Prometheus Operator) et chart `kube-prometheus-stack`.
- Les NetworkPolicies du manifeste ArgoCD autorisent l'accès aux ports de métriques (cibles `up` constatées depuis le namespace `flotte-ops`).
- `for: 5m` : évite une alerte sur un état transitoire (`Progressing` → `Degraded` → `Healthy` pendant un rollout).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Cible `down` : `connection refused` | Port faux (8082 contrôleur, 8083 serveur, 8084 repo-server) | `kubectl get svc -n argocd` |
| Aucune donnée | Moins de 15 s depuis le démarrage | Attendre un intervalle de collecte |
| Pod Prometheus `OOMKilled` | Poste sous-dimensionné | Supprimer après le défi (`kubectl delete -f labs/m07/prometheus-minimal.yaml`) |

## Défi 07.6 ⭐⭐⭐ — Santé d'une ressource personnalisée en Lua
Testé sur un cluster kind séparé (ArgoCD 3.6.1, Kubernetes 1.36).

### Solution
CRD (`livraison-crd.yaml`, appliquée par `kubectl apply`, hors Application) :
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: {name: livraisons.hexa-mobilite.io}
spec:
  group: hexa-mobilite.io
  names: {kind: Livraison, plural: livraisons, singular: livraison}
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      subresources: {status: {}}
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                vehicule: {type: string}
                destination: {type: string}
            status:
              type: object
              properties:
                phase: {type: string, enum: [EnAttente, EnCours, Livree, Echec]}
                message: {type: string}
```
Objet dans `flotte-config` (`apps/livraison/livraison.yaml`) :
```yaml
apiVersion: hexa-mobilite.io/v1
kind: Livraison
metadata:
  name: tournee-lyon-01
spec: {vehicule: VAN-042, destination: Lyon}
```
Avant la règle : colonne `HEALTH` vide pour `Livraison`.

Règle (`health-livraison.yaml`, `kubectl patch cm argocd-cm -n argocd --type merge --patch-file health-livraison.yaml`) :
```yaml
data:
  resource.customizations.health.hexa-mobilite.io_Livraison: |
    hs = {}
    if obj.status == nil or obj.status.phase == nil then
      hs.status = "Progressing"
      hs.message = "En attente de prise en charge"
      return hs
    end
    local phase = obj.status.phase
    if phase == "Livree" then
      hs.status = "Healthy"
    elseif phase == "Echec" then
      hs.status = "Degraded"
    elseif phase == "EnAttente" then
      hs.status = "Suspended"
    else
      hs.status = "Progressing"
    end
    hs.message = obj.status.message or phase
    return hs
```
Test hors cluster (fichier `argocd-cm-test.yaml` = ConfigMap complète contenant la règle) :
```bash
argocd admin settings resource-overrides health liv-echec.yaml --argocd-cm-path argocd-cm-test.yaml
```
```
STATUS: Degraded
MESSAGE: Vehicule en panne
```
Simulation de l'opérateur :
```bash
kubectl patch livraison tournee-lyon-01 -n flotte-livraison --subresource=status --type merge \
  -p '{"status":{"phase":"Echec","message":"Tournee Echec"}}'
```
Mesures (santé de l'Application) : aucun statut → `Progressing` ; `EnCours` → `Progressing` ; `Echec` → `Degraded` ; `Livree` → `Healthy`.

### Pourquoi
- ArgoCD connaît la santé des types natifs et de nombreuses CRD courantes (règles intégrées) ; pour une CRD maison, aucune santé → ressource ignorée dans le calcul.
- Santé de l'Application = la pire santé de ses ressources (`Degraded` > `Progressing` > `Suspended` > `Healthy`, schématiquement) → une tournée en échec rend toute l'Application `Degraded`, donc visible par les notifications et les métriques du M07.
- Test hors cluster : la règle se valide en CI, comme la politique RBAC du Défi 03.7.
- Clé `<GROUPE>_<KIND>` : `_` sépare groupe et type ; groupe vide (`core`) = `_<KIND>` ; joker accepté dans le groupe (`*.hexa-mobilite.io/*`).
- `--subresource=status` : seule façon de modifier `status` quand la sous-ressource est déclarée (un `patch` classique ignore le champ).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Aucun changement de santé | Clé mal formée (`hexa-mobilite.io/Livraison`) | `hexa-mobilite.io_Livraison` |
| `attempt to index a nil value` | `obj.status.phase` lu sans tester `obj.status` | Tester `nil` à chaque niveau |
| Statut inchangé après `kubectl patch` | Patch sans `--subresource=status` | Ajouter l'option (kubectl 1.24+) |
| `Livraison` refusée par le projet | Type absent de `namespaceResourceWhitelist` (si liste restrictive) | Ajouter `{group: hexa-mobilite.io, kind: Livraison}` |

## Défi 07.7 ⭐⭐⭐ — Quand ArgoCD lui-même tombe en panne
Testé sur un cluster kind séparé (ArgoCD 3.6.1, installation non HA).

### Solution
| Composant arrêté | Symptôme visible | Preuve | Applications déjà déployées |
|---|---|---|---|
| `argocd-repo-server` | `Sync Status: Unknown`, condition `ComparisonError` | `Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unavailable desc = connection error: ... dial tcp <IP>:8081: i/o timeout` | Intactes ; aucun nouveau rendu, donc aucun déploiement |
| `argocd-application-controller` | Statut figé `Synced` sur l'ancienne révision, `reconciledAt` ancien ; `argocd app get --refresh` et `argocd app sync` bloqués | Champ `.operation` de l'Application renseigné mais jamais traité | Intactes ; ni synchronisation, ni self-heal, ni détection de dérive |
| `argocd-redis` | API et CLI fonctionnelles (`app list`, `app get`) | Contrôleur : `redis: connection pool: failed to dial after 5 attempts: dial tcp <IP>:6379: i/o timeout` | Intactes ; performances dégradées (cache absent) |

Mesures :
- Repo-server relancé + `--hard-refresh` → `Synced`, condition disparue.
- Contrôleur relancé → opération en attente exécutée en moins de 30 s : nouvelle révision déployée (`destination: Grenoble`), `reconciledAt` mis à jour.

### Pourquoi
- Repo-server = rendu des manifestes (Git, Helm, Kustomize, Jsonnet) → sans lui, l'état cible est inconnu.
- Contrôleur = boucle de réconciliation et exécution des opérations ; l'API écrit la demande de synchronisation dans l'Application (`.operation`), le contrôleur l'exécute → panne silencieuse : l'UI affiche le dernier statut connu, pas une erreur.
- Redis = cache (manifestes rendus, arbre des ressources) ; l'état de référence reste dans les CRD Kubernetes → perte sans conséquence durable.
- Dans tous les cas, les applications déployées continuent de tourner : ArgoCD n'est pas sur le chemin des requêtes.
- Supervision recommandée : alerte sur `up == 0` des cibles ArgoCD (Défi 07.5) et sur l'âge de `reconciledAt`, pas seulement sur la santé des applications.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Terminal bloqué sur `argocd app sync` | Contrôleur arrêté, la CLI attend la fin de l'opération | `Ctrl+C` ou `timeout 20` ; `--async` |
| Contrôleur à 0 après le défi | Oubli de la remise à 1 (StatefulSet) | `kubectl scale sts argocd-application-controller -n argocd --replicas=1` |
| `ComparisonError` persistant après réparation | Cache d'état | `argocd app get <APP> --hard-refresh` |

## Bonus
```yaml
  trigger.flotte-sync-failed: |
    - when: app.status.operationState != nil and app.status.operationState.phase in ['Error', 'Failed']
      send: [flotte-webhook]
```
Abonnement : `notifications.argoproj.io/subscribe.flotte-sync-failed.flotte-alertes: ""`.
Délai attendu : la phase reste `Running` pendant les nouvelles tentatives automatiques (5, délai croissant, environ 5 minutes observées au M05) ; la notification part à l'épuisement des tentatives, ou immédiatement en synchronisation manuelle. Testé : synchronisation manuelle en échec → webhook reçu dans la même seconde ; synchronisation automatique → 5 tentatives, phase `Failed` et webhook environ 5 minutes après le premier essai ; un seul envoi par échec.

## QCM — Réponses
1. **B** — `Synced` : Git est appliqué ; la panne est à l'exécution (événements, journaux).
2. **B** — Le Deployment dépasse `progressDeadlineSeconds` sans progresser : `Degraded`.
3. **B** — Le champ inconnu est ignoré ; l'absence de `containers` rend le manifeste invalide.
4. **A** — `argocd app logs` lit les journaux via l'API ArgoCD (RBAC `logs`).
5. **B** — Trigger, template, service et abonnement.
6. **B** — `argocd_app_info` et son label `health_status`.
7. **B** — Annotation `notifications.argoproj.io/subscribe.<trigger>.<service>`.
