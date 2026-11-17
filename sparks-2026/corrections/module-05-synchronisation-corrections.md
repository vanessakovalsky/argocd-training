# Module 05 — Corrections

Script d'état final du module (testé sur v3.6.1) — mêmes variables que le M04 :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m05/catch-up/m05-final-state.sh
```
État obtenu : synchronisation automatique avec prune et self-heal, 3 réplicas, ConfigMap en vague -1, hooks de migration et de smoke test.

## Lab 05.1 ⭐ — Passer en synchronisation automatique
### Solution
`argocd/flotte-web-dev.yaml`, bloc `syncPolicy` :
```yaml
  syncPolicy:
    automated:
      enabled: true
    syncOptions:
      - CreateNamespace=true
```
Historique observé (testé) :
```
ID      DATE                           REVISION
0       2026-11-08 13:34:00 +0100 CET  main (ef64ceb)
1       2026-11-08 13:35:44 +0100 CET  main (05b6219)
2       2026-11-08 13:45:01 +0100 CET  main (596dad5)
```
Équivalent CLI (non versionné) : `argocd app set flotte-web-dev --sync-policy automated`.

### Pourquoi
- Application modifiée par fichier puis `kubectl apply` : la politique de synchronisation est tracée dans Git.
- `--refresh` : force la comparaison immédiate avec Git au lieu d'attendre la réconciliation (120 s + jitter).
- `enabled: true` explicite : documente l'intention ; `false` suspend l'automatisme en gardant `prune` et `selfHeal`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Rien ne se passe après le push | Délai de réconciliation | `argocd app get flotte-web-dev --refresh` |
| `Sync Policy: Manual` après `kubectl apply` | `automated` mal indenté (hors de `syncPolicy`) | Comparer au modèle `labs/m05/flotte-web-dev-auto.yaml` |
| Modification de l'Application annulée plus tard | Application modifiée par `argocd app set`, puis fichier réappliqué | Une seule source : le fichier YAML |

## Lab 05.2 ⭐ — Dérive et self-heal
### Solution
Diff observé sans self-heal (testé) :
```
===== apps/Deployment flotte-dev/flotte-web ======
147c147
<   replicas: 5
---
>   replicas: 3
```
Bloc `automated` après l'étape 2 :
```yaml
    automated:
      enabled: true
      selfHeal: true
```
Retour à 3 réplicas mesuré en moins de 15 s.

### Pourquoi
- Sans self-heal, la synchronisation automatique ne se relance pas : le commit `596dad5` a déjà été synchronisé avec succès (une tentative par commit).
- Self-heal : nouvelle synchronisation 5 s après la détection de l'écart (`--self-heal-timeout-seconds` du contrôleur).
- Lignes `<` = état du cluster, `>` = état souhaité (Git).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Dérive non détectée | Champ ignoré (`ignoreDifferences`) ou ressource exclue | `argocd app get -o yaml`, rubrique `ignoreDifferences` |
| Self-heal « trop efficace » pendant un dépannage | Comportement attendu | `automated.enabled: false` le temps de l'intervention, puis correction dans Git |

## Exercice 05.3 ⭐⭐ — Supprimer ce qui a quitté Git
### Solution
```yaml
# apps/flotte-web/legacy-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flotte-web-legacy
data:
  mode: "ancien"
```
Après retrait du fichier, sans prune (testé) :
```
Sync Status:        OutOfSync from main (728b098)
       ConfigMap   flotte-dev  flotte-web-legacy  OutOfSync                 configmap/flotte-web-legacy created
```
Après `prune: true` et rafraîchissement (testé) :
```
Sync Status:        Synced to main (728b098)
       ConfigMap   flotte-dev  flotte-web-legacy  Succeeded  Pruned         pruned
```
Protections : annotation `argocd.argoproj.io/sync-options: Prune=false` sur la ressource ; synchronisation manuelle de l'environnement ; option `Delete=false` (conservée même à la suppression de l'Application).

### Pourquoi
- Prune désactivé par défaut : une erreur de chemin ou de branche supprimerait toute l'application.
- Activation non immédiate : la prochaine réconciliation (ou le self-heal, actif ici) déclenche la synchronisation avec prune.
- La colonne `MESSAGE` conserve `created` (dernière opération sur la ressource) tant qu'aucune nouvelle synchronisation ne l'a modifiée.

### Variantes acceptables
- Synchronisation manuelle ponctuelle avec prune : `argocd app sync flotte-web-dev --prune`.
- Suppression avec confirmation : annotation `argocd.argoproj.io/sync-options: Prune=confirm`.

## Lab 05.4 ⭐⭐ — Hooks et sync waves
### Solution
Fichiers `labs/m05/hook-presync-migration.yaml` et `labs/m05/hook-postsync-smoke-test.yaml`. Smoke test :
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: flotte-smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: smoke-test
          image: curlimages/curl:8.17.0
          command: ["curl", "-fsS", "--retry", "5", "--retry-connrefused", "http://flotte-web/readyz"]
```
Résultat de synchronisation (testé) :
```
GROUP  KIND        NAMESPACE   NAME                 STATUS     HEALTH   HOOK      MESSAGE
batch  Job         flotte-dev  flotte-db-migration  Succeeded  Synced   PreSync   Reached expected number of succeeded pods
       ConfigMap   flotte-dev  flotte-web-config    Synced                        configmap/flotte-web-config configured
       Service     flotte-dev  flotte-web           Synced     Healthy            service/flotte-web unchanged
apps   Deployment  flotte-dev  flotte-web           Synced     Healthy            deployment.apps/flotte-web unchanged
batch  Job         flotte-dev  flotte-smoke-test    Succeeded  Synced   PostSync  Reached expected number of succeeded pods
```
Réponse à l'étape 5 : politique `BeforeHookCreation` ; chaque Job est conservé jusqu'à la synchronisation suivante, qui le supprime juste avant d'en créer un nouveau. Avantage : résultat et journaux consultables après coup.

### Pourquoi
- `backoffLimit: 0` et `restartPolicy: Never` : un échec est définitif et immédiat (pas de nouvelle tentative du Job lui-même).
- `--retry` de curl : le Service peut mettre quelques secondes à router vers les nouveaux pods.
- Smoke test sur `/readyz` : point de terminaison de disponibilité de podinfo.
- Vague -1 pour la ConfigMap : la configuration existe avant le Deployment qui la consomme.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Hook non exécuté | Synchronisation sélective (quelques ressources cochées) | Synchronisation complète |
| `field is immutable` sur un Job | Job modifié et réappliqué sans suppression | Politique `BeforeHookCreation` (ou `generateName`) |
| Smoke test en échec `Could not resolve host` | Nom du Service erroné | `kubectl get svc -n flotte-dev` |
| Annotation `sync-wave` ignorée | Valeur non entre guillemets (`-1` au lieu de `"-1"`) | Les annotations sont des chaînes |

## Défi 05.5 ⭐⭐⭐ — Migration en échec et champ géré ailleurs
### Solution
```bash
sed -i 's/podinfo:6.15.0/podinfo:6.16.0/' apps/flotte-web/deployment.yaml
sed -i "s/echo 'OK'\"\]/echo 'ERREUR schema'; exit 1\"]/" apps/flotte-web/hook-presync-migration.yaml
git commit -am "feat: 6.16.0 + migration" && git push
argocd app get flotte-web-dev --refresh > /dev/null
```
Observations (testées) :
- Image du Deployment toujours `ghcr.io/stefanprodan/podinfo:6.15.0`.
- Opération : `Running | one or more synchronization tasks completed unsuccessfully. Retrying attempt #5 at <DATE>.` (5 tentatives, délai croissant, environ 5 minutes au total).
- Job `flotte-db-migration` : statut `Failed`, hook `PreSync`, message `Job has reached the specified backoff limit`.

Réparation :
```bash
argocd app terminate-op flotte-web-dev
sed -i "s/echo 'ERREUR schema'; exit 1\"\]/echo 'OK'\"]/" apps/flotte-web/hook-presync-migration.yaml
git commit -am "fix: migration corrigee" && git push
argocd app get flotte-web-dev --refresh > /dev/null
argocd app wait flotte-web-dev --sync --health
```
Résultat : `Synced`, image `6.16.0`, migration et smoke test `Succeeded`.

Champ géré ailleurs :
```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: flotte-web
      jsonPointers: [/spec/replicas]
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
```
Testé : `kubectl scale --replicas=4` → application `Synced`, 4 réplicas conservés malgré le self-heal ; retrait du bloc → retour à 3 réplicas.

### Pourquoi
- Un commit en échec n'est pas retenté indéfiniment : la correction passe par un nouveau commit (traçabilité de la réparation).
- `terminate-op` : stoppe les tentatives en cours, utile avant de pousser le correctif.
- Sans `RespectIgnoreDifferences=true` : l'écart est masqué, mais une synchronisation déclenchée par un autre changement réappliquerait `replicas` depuis Git.
- En production avec HPA : retirer plutôt `replicas` du manifeste, et garder `ignoreDifferences` pour les cas où le champ est imposé (chart tiers).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `sed` sans effet sur le hook | Guillemets du motif différents du fichier | Modifier le fichier à la main |
| Nouvelle version déployée malgré l'échec | Migration en `Sync` (pas `PreSync`) ou en vague plus haute | Vérifier l'annotation `hook` |
| Réplicas remis à 3 malgré `ignoreDifferences` | `RespectIgnoreDifferences=true` absent | Ajouter l'option |

## Défi 05.6 ⭐⭐⭐ — Suppression sous confirmation humaine
Testé sur un cluster kind séparé (ArgoCD 3.6.1, synchronisation automatique avec `prune: true`).

### Solution
`apps/flotte-web/cm-legacy.yaml` :
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flotte-legacy
  annotations:
    argocd.argoproj.io/sync-options: Prune=confirm
data:
  mode: legacy
```
```bash
git add apps/ && git commit -m "feat: configmap flotte-legacy" && git push
git rm apps/flotte-web/cm-legacy.yaml && git commit -m "chore: retrait flotte-legacy" && git push
argocd app get flotte-web-dev --refresh
```
État mesuré :
```
OutOfSync | Running | waiting for pruning confirmation of /ConfigMap/flotte-legacy
```
Accord :
```bash
argocd app confirm-deletion flotte-web-dev
```
Résultat mesuré : `Application 'flotte-web-dev' updated successfully`, puis `Synced | Succeeded`, ConfigMap supprimée. Trace sur l'Application : annotation `argocd.argoproj.io/deletion-approved: "<HORODATAGE>"`.

### Pourquoi
- `Prune=confirm` : l'opération reste `Running` en attente → aucune autre synchronisation de l'Application tant que l'accord n'est pas donné (blocage visible, voulu).
- Accord = annotation horodatée sur l'Application (`confirm-deletion` ou bouton *Confirm* de l'UI) : valable pour les élagages en attente à cet instant.
- `Prune=false` : la ressource n'est jamais supprimée et l'Application reste `OutOfSync` (ressource à élaguer) ; suppression manuelle nécessaire.
- Choix : `confirm` = suppression prévue mais validée (données, PVC, ressources partagées) ; `false` = ressource à conserver durablement hors Git.
- Équivalent pour la suppression de l'Application : `Delete=confirm`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| ConfigMap supprimée sans attente | Annotation ajoutée dans le même commit que le retrait, ou faute de frappe (`prune=confirm`) | Annotation présente sur l'objet vivant avant le retrait de Git |
| Nouveau commit non déployé | Opération toujours en attente de confirmation | Confirmer, ou `argocd app terminate-op flotte-web-dev` |
| `permission denied` sur `confirm-deletion` | Compte sans droit de mise à jour de l'Application | Contexte administrateur ou `ops-bob` |

## Défi 05.7 ⭐⭐⭐ — Namespace géré par ArgoCD et Pod Security restreinte
Testé sur un cluster kind séparé (ArgoCD 3.6.1, Kubernetes 1.36, `podinfo:6.16.0`).

### Solution
Application :
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-web-secure
  namespace: argocd
spec:
  project: flotte
  source:
    repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
    targetRevision: main
    path: apps/flotte-web-secure
  destination:
    server: https://kubernetes.default.svc
    namespace: flotte-secure
  syncPolicy:
    automated: {}
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: restricted
        hexa-mobilite/equipe: dev
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```
Itérations mesurées :

| Étape | Statut ArgoCD | Pods | Cause (`kubectl get events -n flotte-secure`) |
|---|---|---|---|
| Manifestes du Lab 04.1 | `Synced` / `Progressing` | 0 (ReplicaSet `0/1`) | `violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true` |
| + `securityContext` sans UID | `Synced` / `Progressing` | `CreateContainerConfigError` | `container has runAsNonRoot and image has non-numeric user (app), cannot verify user is non-root` |
| + `runAsUser: 10001` | `Synced` / `Healthy` | `1/1 Running` | — |

`securityContext` final (extrait du Deployment) :
```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: flotte-web
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
```
Gestionnaires de champs du Deployment : `argocd-controller` (`Apply`), `kube-controller-manager` (`Update`, statut).

Libellé passé à `ops` dans l'Application : Application `OutOfSync`, namespace inchangé tant qu'aucune synchronisation n'a lieu ; `argocd app sync flotte-web-secure` → libellé `hexa-mobilite/equipe=ops`.

### Pourquoi
- `Synced` ≠ fonctionnel : ArgoCD a appliqué le Deployment ; c'est le ReplicaSet qui se voit refuser les pods → diagnostic dans les événements, pas dans ArgoCD.
- `managedNamespaceMetadata` : libellés et annotations du namespace décrits dans l'Application, appliqués à chaque synchronisation (namespace créé ou existant).
- Synchronisation automatique déclenchée par une nouvelle révision Git ou un écart de ressource, pas par la seule modification de cette section de l'Application → synchronisation manuelle (mesuré).
- `ServerSideApply=true` : fusion par le serveur, propriété des champs tracée (`managedFields`) ; utile avec d'autres gestionnaires (HPA, opérateurs) et pour les gros objets (CRD > 256 Ko d'annotation `last-applied`).
- Image `podinfo` : utilisateur `app` non numérique → `runAsUser` explicite obligatoire avec `runAsNonRoot`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Libellés absents du namespace | Namespace créé avant, hors ArgoCD, et aucune synchronisation depuis | Synchroniser ; ou supprimer le namespace (laboratoire uniquement) |
| `seccompProfile` exigé | Profil `restricted` : `RuntimeDefault` ou `Localhost` obligatoire | Ajouter au niveau du pod |
| Santé `Degraded` après 10 min | `progressDeadlineSeconds` dépassé (600 s) | Corriger, pousser ; le Deployment repasse `Progressing` |

## Bonus
Hook `SyncFail` :
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: flotte-sync-fail
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: alerte
          image: busybox:1.37
          command: ["sh", "-c", "echo 'Echec de synchronisation flotte-web'"]
```
Testé (synchronisation manuelle, migration en échec) : Job `flotte-sync-fail` `Complete`, journal `Echec de synchronisation flotte-web`. Après une synchronisation `SyncFail`, la commande `argocd app sync` se termine par `Operation has completed with phase: Failed`.

Pause de l'automatisme (testé) : `automated.enabled: false` → `Sync Policy: Manual`, commit suivant non déployé (`OutOfSync`) ; réactivation → déployé en moins d'une minute, `Sync Policy: Automated (Prune)`.

## QCM — Réponses
1. **B** — Sans prune, la ressource orpheline reste en place et l'application est `OutOfSync`.
2. **B** — Self-heal resynchronise environ 5 s après la détection de l'écart.
3. **A** — `enabled: false` suspend l'automatisme en conservant `prune` et `selfHeal`.
4. **B** — `PreSync` s'exécute avant l'application des manifestes.
5. **B** — Un hook `PreSync` en échec arrête la synchronisation : les ressources ne sont pas modifiées.
6. **C** — Les vagues sont appliquées de la plus basse à la plus haute.
7. **B** — Sans cette option, l'écart est seulement masqué dans le diff, puis écrasé lors d'une synchronisation.
8. **C** — Sans politique explicite, `BeforeHookCreation` s'applique.
