# Module 12 — Corrections

Script d'état final du module (testé sur v3.6.1) — mêmes variables que le M04 :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m12/catch-up/m12-final-state.sh
```
État obtenu : ApplicationSet `flotte-web` versionné dans `flotte-config/argocd/`, générant `flotte-web-dev` et `flotte-web-recette`.

## Lab 12.1 ⭐⭐ — Générer les environnements avec un ApplicationSet
### Solution
`labs/m12/applicationset-flotte-web.yaml` (extrait) :
```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
        revision: main
        directories:
          - path: apps/flotte-web/overlays/*
          - path: apps/flotte-web/overlays/prod
            exclude: true
  template:
    metadata:
      name: 'flotte-web-{{.path.basename}}'
```
Observations (testées) :
```
NAME                       NAMESPACE       STATUS  HEALTH
argocd/flotte-web-demo     flotte-demo     Synced  Healthy
argocd/flotte-web-dev      flotte-dev      Synced  Healthy
argocd/flotte-web-recette  flotte-recette  Synced  Healthy
```
Après suppression du dossier `demo` : Application `flotte-web-demo` et ses ressources supprimées ; namespace `flotte-demo` conservé (créé par `CreateNamespace`).

### Pourquoi
- `goTemplate` + `missingkey=error` : une variable mal nommée fait échouer la génération au lieu de produire un nom vide.
- `{{.path.basename}}` = nom du dossier (`dev`, `recette`) ; `{{.path.path}}` = chemin complet.
- Adoption : les Applications existantes de même nom passent sous le contrôle de l'ApplicationSet (`ownerReferences`) ; leurs fichiers individuels dans `argocd/` deviennent obsolètes.
- Annotations de notification reprises dans le modèle : sans elles, l'adoption aurait supprimé les abonnements du M07.
- Rafraîchissement manuel du générateur : sans annotation, prise en compte à la réconciliation suivante (délai de quelques minutes).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `ErrorOccurred=True` : `map has no entry for key` | Variable de modèle erronée | `{{.path.basename}}` (avec `goTemplate: true`) |
| Application `prod` générée | Exclusion absente ou chemin faux | Bloc `exclude: true` sur le chemin exact |
| Application refusée par le projet | Dépôt de l'ApplicationSet différent de `sourceRepos` | URL identique à celle du projet |
| Abonnements de notification perdus | Annotations absentes du modèle | Les ajouter dans `template.metadata.annotations` |

## Exercice 12.2 ⭐ — Sauvegarder la configuration d'ArgoCD
### Solution
Sortie observée (testée) :
```
      3 kind: Application
      1 kind: ApplicationSet
      2 kind: AppProject
      4 kind: ConfigMap
      3 kind: Secret
```
Absents de la sauvegarde : contenu des dépôts Git (sauvegardé par la forge), clé privée de Sealed Secrets (M11), contrôleurs installés à part (Argo Rollouts, Sealed Secrets), ressources déployées et leurs données (volumes), configuration du cluster lui-même.

Stockage : coffre ou stockage objet chiffré, accès restreint, hors Git ; fréquence quotidienne et avant chaque mise à niveau ; restauration testée (`argocd admin import -n argocd - < argocd-backup.yaml`) sur un cluster de recette.

### Pourquoi
- Les Secrets d'ArgoCD (dépôts, comptes, webhook, clé de session) rendent le fichier aussi sensible qu'un accès administrateur.
- Avec un ArgoCD géré par Git (*self-managed*, App of Apps), la sauvegarde complète Git, sans le remplacer.

## Exercice 12.3 ⭐⭐ — Plan de mise à niveau
### Solution
1. Lire les notes `upgrading/3.4-3.5.md` puis `upgrading/3.5-3.6.md` ; relever changements incompatibles et actions préalables.
2. Sauvegarde (`argocd admin export`) et clé de Sealed Secrets.
3. Recette : appliquer le manifeste 3.5 (`kubectl apply --server-side --force-conflicts`), vérifier pods, applications `Synced` / `Healthy`, connexion SSO, notifications.
4. Production 3.5 dans une fenêtre de maintenance ; observation.
5. Recommencer pour 3.6.
6. Retour arrière : réappliquer le manifeste de la version précédente et restaurer la sauvegarde si un changement de schéma l'exige (à vérifier dans les notes de version).

### Pourquoi
- Correctifs fournis pour les 3 dernières versions mineures seulement : rester à jour limite l'exposition aux failles.
- Une version à la fois : chaque note de mise à niveau décrit l'écart avec la version précédente uniquement.

## Étude de cas 12.4 ⭐⭐ — *Transports Régionaux Sud*
### Proposition type
| Thème | Proposition |
|---|---|
| Dépôts | Un dépôt de code par équipe ; un dépôt de configuration par équipe (`<equipe>-config`) ; un dépôt plateforme (ArgoCD, projets, ApplicationSets) |
| Projets | Un AppProject par équipe : dépôts de l'équipe, destinations `<equipe>-*` sur les clusters autorisés, ressources de cluster interdites |
| Identité | OIDC de l'annuaire ; groupes → `role:dev` limité au projet, plateforme → `role:admin` ; `admin` désactivé |
| Génération | ApplicationSet par équipe : générateur matriciel `git` (services) × `clusters` (étiquettes `env`, `region`) |
| Livraison | Recette : synchronisation automatique, canari avec analyse ; production : synchronisation manuelle, fenêtres `allow` mardi et jeudi 7 h-9 h (`syncWindows`), merge request validée par le responsable plateforme |
| Secrets | External Secrets Operator relié au coffre existant |
| Incident du correctif écrasé | Correctif par commit (revert ou patch), self-heal en production pour rendre visible toute modification manuelle, procédure d'urgence documentée (M06) |
| Cluster de secours | Argo CD Agent sur le cluster de secours, ou instance ArgoCD locale pilotée par le même dépôt plateforme |
| Exploitation | Notifications vers l'outil d'astreinte, alertes Prometheus `Degraded` > 10 min, sharding du contrôleur (3 clusters de production + 2 de recette) |

Schéma attendu : dépôts (code, configuration, plateforme) → ArgoCD central (HA) → clusters de recette et de production des 2 régions ; agent sur le cluster de secours ; flux CI → dépôts de configuration.

### Critères d'évaluation de la restitution
- Chaque contrainte traitée (fenêtres, validation, OIDC, coffre, incident, secours).
- Moindre privilège visible (projets par équipe, pas d'accès cluster pour la CI).
- Réalisme de l'exploitation (sauvegarde, mise à niveau, alertes).

## Défi 12.5 ⭐⭐⭐ — Application racine
### Solution
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hexa-racine
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
    targetRevision: main
    path: argocd
    directory:
      exclude: "{flotte-web-dev.yaml,flotte-web-recette.yaml}"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
```
Résultats (testés) :
```
argoproj.io  Application     argocd  flotte-api-dev   Synced  application.argoproj.io/flotte-api-dev configured
argoproj.io  ApplicationSet  argocd  flotte-web       Synced  applicationset.argoproj.io/flotte-web configured
argoproj.io  Application     argocd  flotte-web-prod  Synced  application.argoproj.io/flotte-web-prod created
```
`flotte-web-prod` : `OutOfSync` / `Missing`, politique `Manual` (non déployée tant qu'aucune synchronisation n'est demandée).

Suppression non cascadée : `argocd app delete hexa-racine --cascade=false` → Applications enfants conservées (testé).

### Pourquoi
- Projet `default` pour la racine : le projet `flotte` n'autorise ni le namespace `argocd` comme destination ni la gestion d'Applications ; en production, un projet « plateforme » dédié.
- Exclusion des fichiers `flotte-web-dev.yaml` et `flotte-web-recette.yaml` : sinon deux propriétaires (racine et ApplicationSet) se disputeraient les mêmes Applications.
- Finalizer : sans `resources-finalizer.argocd.argoproj.io` sur la racine (ou avec `--cascade=false`), sa suppression laisse les enfants ; avec, toute la plateforme serait supprimée en cascade.

## Défi 12.6 ⭐⭐⭐ — Environnements × régions : générateur matrix
Testé sur un cluster kind séparé (ArgoCD 3.6.1, overlays Kustomize simplifiés `dev` et `recette`).

### Solution
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: flotte-regions
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
              revision: main
              directories:
                - path: apps/flotte-web/overlays/*
                - path: apps/flotte-web/overlays/prod
                  exclude: true
          - list:
              elements:
                - {region: nord, replicas: "1"}
                - {region: sud, replicas: "2"}
  template:
    metadata:
      name: 'flotte-web-{{.path.basename}}-{{.region}}'
      labels:
        env: '{{.path.basename}}'
        region: '{{.region}}'
    spec:
      project: flotte
      source:
        repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
        targetRevision: main
        path: '{{.path.path}}'
        kustomize:
          replicas:
            - name: flotte-web
              count: '{{.replicas}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'flotte-{{.path.basename}}-{{.region}}'
      syncPolicy:
        syncOptions: [CreateNamespace=true]
  templatePatch: |
    {{- if eq .path.basename "dev" }}
    spec:
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
    {{- end }}
```
Mesures :
```
ErrorOccurred=False      All applications have been generated successfully
ParametersGenerated=True All parameters have been generated successfully
ResourcesUpToDate=True   All applications have been generated successfully

argocd/flotte-web-dev-nord      flotte-dev-nord      Synced     Healthy  Auto-Prune
argocd/flotte-web-dev-sud       flotte-dev-sud       Synced     Healthy  Auto-Prune
argocd/flotte-web-recette-nord  flotte-recette-nord  OutOfSync  Missing  Manual
argocd/flotte-web-recette-sud   flotte-recette-sud   OutOfSync  Missing  Manual
```
Réplicas : `flotte-dev-nord` 1, `flotte-dev-sud` 2. Lors du test, le premier rendu de `dev-nord` affichait 2 réplicas ; un `argocd app get flotte-web-dev-nord --hard-refresh` a donné 1 (cache de rendu).

Avec `count: {{.replicas}}` (sans guillemets), refus mesuré à l'application de l'ApplicationSet :
```
error converting YAML to JSON: yaml: invalid map key: map[interface {}]interface {}{".replicas":interface {}(nil)}
```

### Pourquoi
- `matrix` : produit cartésien des paramètres de deux générateurs (2 dossiers × 2 régions = 4 Applications) ; chaque Application reçoit `path.*` et `region`, `replicas`.
- `{{...}}` non entre guillemets = objet YAML (accolades) → le fichier n'est plus du YAML valide avant même le rendu ; `'{{.replicas}}'` = chaîne, acceptée par `count` (entier ou chaîne).
- `templatePatch` : texte rendu **avant** l'analyse YAML → structures conditionnelles (`if`), impossibles dans `template` ; utile pour la politique de synchronisation, les `ignoreDifferences` ou des sources propres à un environnement.
- Libellés `env` / `region` sur les Applications : filtres de l'UI (`argocd app list -l env=dev`), sélection dans les stratégies progressives (Défi 12.7) et RBAC par projet.
- Ajouter une région = une ligne dans la liste ; ajouter un environnement = un dossier.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `invalid map key` | Expression Go template non entre guillemets dans `template` | `'{{.x}}'`, ou déplacer dans `templatePatch` |
| `map has no entry for key "region"` | `missingkey=error` et paramètre absent d'un élément de liste | Même clés dans tous les éléments |
| Applications en double nom | Nom sans la région | `flotte-web-{{.path.basename}}-{{.region}}` |

## Défi 12.7 ⭐⭐⭐ — Livraison progressive entre Applications
Testé sur un cluster kind séparé (ArgoCD 3.6.1), à partir de l'ApplicationSet du Défi 12.6 (synchronisation automatique pour les 4 Applications).

### Solution
```bash
kubectl patch cm argocd-cmd-params-cm -n argocd --type merge \
  -p '{"data":{"applicationsetcontroller.enable.progressive.syncs":"true"}}'
kubectl rollout restart deploy/argocd-applicationset-controller -n argocd
```
Ajout à l'ApplicationSet :
```yaml
spec:
  strategy:
    type: RollingSync
    rollingSync:
      steps:
        - matchExpressions:
            - {key: env, operator: In, values: [dev]}
        - matchExpressions:
            - {key: env, operator: In, values: [recette]}
          maxUpdate: 1
```
Politique relevée sur une Application générée :
```
{"automated":{"enabled":false,"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}
```
Chronologie mesurée après le push d'une nouvelle image (échantillon toutes les 8 à 10 s, ordre : dev-nord dev-sud recette-nord recette-sud) :
```
17:28:51 dev-nord=Waiting  dev-sud=Waiting     recette-*=Waiting | 6.17.0 6.17.0 6.17.0 6.17.0
17:28:59 dev-nord=Healthy  dev-sud=Progressing recette-*=Waiting | 6.16.0 6.16.0 6.17.0 6.17.0
17:29:08 dev-nord=Healthy  dev-sud=Healthy     recette-*=Healthy | 6.16.0 6.16.0 6.16.0 6.16.0
```
Fin : retirer `strategy`, remettre la clé à `"false"` (ou la supprimer), redémarrer le contrôleur d'ApplicationSet, supprimer l'ApplicationSet.

### Pourquoi
- Avec `RollingSync`, le contrôleur d'ApplicationSet désactive l'automatisme des Applications (`enabled: false`) et déclenche lui-même les synchronisations, étape par étape ; l'étape suivante attend que les Applications de l'étape courante soient `Healthy`.
- `maxUpdate` : nombre (ou pourcentage) d'Applications synchronisées simultanément dans une étape ; à l'échantillonnage de 10 s, les deux `recette` sont passées dans le même intervalle (synchronisation rapide) — un intervalle plus court ou des applications plus lentes montrent l'enchaînement.
- Différence avec Argo Rollouts : Rollouts répartit le **trafic** entre deux versions d'une même application ; Progressive Syncs ordonne le **déploiement** de plusieurs Applications (environnements, régions, clusters). Les deux se combinent.
- Bêta (depuis 3.3) : désactivée par défaut, comportement susceptible d'évoluer → à valider sur une version précise avant usage en production.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Stratégie ignorée, tout part en même temps | Fonctionnalité non activée ou contrôleur non redémarré | Clé dans `argocd-cmd-params-cm` + `rollout restart` |
| Étape 2 bloquée en `Waiting` | Une Application de l'étape 1 reste `Progressing` ou `Degraded` | Réparer l'étape 1 ; l'étape 2 suit automatiquement |
| Application jamais sélectionnée | Libellé absent du modèle (`metadata.labels`) | Libellés `env` dans `template.metadata.labels` |

## Bonus
Source Hydrator (bêta depuis 3.5) : ArgoCD rend les manifestes (Helm, Kustomize) et écrit le résultat dans une branche Git dédiée ; les relecteurs voient le YAML final appliqué au cluster au lieu des seules modifications de valeurs ou de patchs ; la synchronisation se fait depuis ces manifestes rendus.

## QCM — Réponses
1. **B** — Seules les trois versions mineures les plus récentes reçoivent des correctifs.
2. **B** — Applications, projets, ApplicationSets, ConfigMaps et Secrets d'ArgoCD.
3. **B** — L'Application générée disparaît avec ses ressources (politique `sync` par défaut).
4. **B** — Un agent par cluster (Argo CD Agent) quand le hub ne peut pas joindre les clusters.
5. **B** — Les fenêtres de synchronisation (`syncWindows`) de l'AppProject.
6. **B** — Il écrit dans Git les manifestes rendus.
7. **B** — La mise à niveau se résume à changer l'URL de version dans le `kustomization.yaml`.
