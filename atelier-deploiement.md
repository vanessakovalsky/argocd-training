# Atelier 3.1 : Déployer votre première application
## Pré-requis

* Créer un dépôt sur github et forker le dépôt : https://github.com/argoproj/argocd-example-apps

```bash
# Forker https://github.com/argoproj/argocd-example-apps

# Cloner votre fork
git clone https://github.com/VOTRE_USERNAME/argocd-example-apps
cd argocd-example-apps/guestbook
```

#### Objectif
Déployer une application simple avec ArgoCD en utilisant les manifestes d'exemple.

#### Partie 1 : Application avec plain YAML

**Étape 1 : Créer le manifeste d'application**

```yaml
# app-guestbook.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

**Étape 2 : Déployer l'application**

```bash
# Via kubectl
kubectl apply -f app-guestbook.yaml

# OU via la CLI
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace guestbook \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Vérifier le statut
argocd app get guestbook

# Synchroniser manuellement si nécessaire
argocd app sync guestbook
```

**Étape 3 : Observer la synchronisation**

```bash
# Suivre la synchronisation en temps réel
argocd app wait guestbook

# Vérifier les ressources déployées
kubectl get all -n guestbook

# Voir les logs
kubectl logs -n guestbook deployment/guestbook-ui
```

**Étape 4 : Explorer l'interface web**

1. Ouvrir ArgoCD UI
2. Cliquer sur l'application "guestbook"
3. Observer le graphe des ressources
4. Cliquer sur les différentes ressources pour voir les détails

#### Partie 2 : Application avec Helm

**Étape 1 : Créer une application Helm**

```yaml
# app-nginx-helm.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-helm
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 22.2.4
    helm:
      parameters:
      - name: service.type
        value: ClusterIP
      - name: replicaCount
        value: "2"
      values: |
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
  
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx
  
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
```

**Étape 2 : Déployer**

```bash
# Appliquer
kubectl apply -f app-nginx-helm.yaml

# Vérifier
argocd app get nginx-helm
argocd app sync nginx-helm
```

**Étape 3 : Modifier les paramètres**

```bash
# Via CLI
argocd app set nginx-helm \
  --helm-set replicaCount=3

# Synchroniser
argocd app sync nginx-helm

# Vérifier
kubectl get deployment -n nginx
```

#### Points de validation
- [ ] Application guestbook déployée et Synced
- [ ] Toutes les ressources sont Healthy
- [ ] Application nginx-helm déployée avec Helm
- [ ] Paramètres Helm modifiés avec succès
- [ ] Compréhension du graphe de ressources dans l'UI

---

### Atelier 3.2 : Synchronisation et gestion d'état (45 min)

#### Objectif
Comprendre les différents états de synchronisation et apprendre à gérer les dérives.

#### Partie 1 : Créer une dérive manuelle

**Étape 1 : Modifier une ressource manuellement**

```bash
# Scaler le deployment guestbook
kubectl scale deployment guestbook-ui -n guestbook --replicas=5

# Vérifier l'état dans ArgoCD
argocd app get guestbook

# Status devrait être "OutOfSync" si syncro manuelle
```

**Étape 2 : Observer la dérive dans l'UI**

1. Aller dans l'application guestbook
2. Observer l'icône "OutOfSync" ou "Synced" selon le selfHeal
3. Cliquer sur "App Diff" pour voir les différences

**Étape 3 : Tester le self-heal**

Si `selfHeal: true` est activé :
- ArgoCD corrigera automatiquement la dérive dans les 3 minutes
- Observer la correction automatique

Si `selfHeal: false` :
```bash
# Synchroniser manuellement
argocd app sync guestbook
```

#### Partie 2 : Tester le prune

**Étape 1 : Ajouter une ressource**

* Créer le fichier cm.yaml
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-config
  namespace: guestbook
data:
  key: value
```
* Puis le commiter et le push
* Observer argocd déployer votre config map

**Étape 2 : Vérifier que la ressource est gérée**

```bash
# Lister les ressources gérées
argocd app resources guestbook

# Le ConfigMap devrait apparaître
```

**Étape 3 : Activer le prune et synchroniser**

* Supprimer votre fichier du git (et faite un commit / push)

```bash
# Si prune n'est pas activé, l'activer
argocd app set guestbook --sync-option Prune=true

# Synchroniser
argocd app sync guestbook --prune

# Vérifier que le ConfigMap a été supprimé
kubectl get configmap test-config -n guestbook
# Error: not found
```

**Étape 4 : Ajouter une ressource manuellement**

```bash
# Créer un ConfigMap non géré par Git
kubectl create configmap manual-config \
  -n guestbook \
  --from-literal=key=value
```

**Étape 5 : Vérifier que la ressource n'est pas gérée**

```bash
# Lister les ressources gérées
argocd app resources guestbook

# Le ConfigMap manuel ne devrait pas apparaître
```

**Étape 6 : Activer le prune et synchroniser**

```bash
# Si prune n'est pas activé, l'activer
argocd app set guestbook --sync-option Prune=true

# Synchroniser
argocd app sync guestbook --prune

# Vérifier que le ConfigMap manuel n'a pas été supprimé
kubectl get configmap manual-config -n guestbook
```

-> argocd ne gère que les ressources qu'il connait. Si vous créez des ressources manuellement et hors dépôt git, celle ci ne sont pas gérée.

#### Partie 3 : Ignorer des différences

**Créer une application avec ignoreDifferences :**

```yaml
# app-with-hpa.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-with-hpa
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: hpa-test
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
  
  # Ignorer les replicas (géré par HPA)
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
```

**Tester :**
```bash
# Déployer
kubectl apply -f app-with-hpa.yaml
argocd app sync app-with-hpa

# Modifier les replicas
kubectl scale deployment guestbook-ui -n hpa-test --replicas=10

# Vérifier que l'app reste Synced
argocd app get app-with-hpa
# Devrait rester "Synced" malgré le changement
```

#### Points de validation
- [ ] Dérive manuelle créée et détectée
- [ ] Self-heal fonctionne correctement
- [ ] Prune supprime les ressources non gérées
- [ ] ignoreDifferences fonctionne comme prévu

---

### Atelier 3.3 : Rollback et historique

#### Objectif
Apprendre à gérer l'historique et effectuer des rollbacks.

#### Partie 1 : Créer plusieurs révisions

**Étape 1 : Modifier l'application plusieurs fois**

```bash
# Modification 1 : Changer l'image
# Éditer guestbook-ui-deployment.yaml
# Changer l'image de gcr.io/heptio-images/ks-guestbook-demo:0.1
# à gcr.io/heptio-images/ks-guestbook-demo:0.2

git add .
git commit -m "Update to version 0.2"
git push

# Attendre la synchronisation ou sync manuel
argocd app sync guestbook

# Modification 2 : Augmenter les replicas
# Éditer guestbook-ui-deployment.yaml
# Changer replicas: 1 à replicas: 3

git add .
git commit -m "Scale to 3 replicas"
git push

argocd app sync guestbook
```

#### Partie 2 : Explorer l'historique

```bash
# Voir l'historique complet
argocd app history guestbook

# Output exemple:
# ID  DATE                           REVISION
# 0   2024-10-29 10:00:00 +0000 UTC  abc123 (Initial deploy)
# 1   2024-10-29 10:15:00 +0000 UTC  def456 (Update to version 0.2)
# 2   2024-10-29 10:30:00 +0000 UTC  ghi789 (Scale to 3 replicas)

# Voir les détails d'une révision
argocd app manifests guestbook --revision 1
```

#### Partie 3 : Effectuer un rollback

```bash
# Rollback vers la révision 1
argocd app rollback guestbook 1

# Vérifier les ressources
kubectl get deployment guestbook-ui -n guestbook -o yaml | grep image
kubectl get deployment guestbook-ui -n guestbook -o yaml | grep replicas

# Voir le nouvel historique
argocd app history guestbook
# Une nouvelle révision sera créée
```

#### Partie 4 : Rollback via Git (méthode recommandée)

```bash
# Dans votre dépôt Git local
git log --oneline
# abc123 Scale to 3 replicas
# def456 Update to version 0.2
# 123abc Initial deploy

# Revert le dernier commit
git revert HEAD --no-edit
git push

# ArgoCD synchronisera automatiquement
argocd app sync guestbook --watch
```

#### Points de validation
- [ ] Historique des révisions affiché correctement
- [ ] Rollback via CLI réussi
- [ ] Rollback via Git réussi
- [ ] Compréhension de la différence entre les deux méthodes


## Ateliers bonus — Déploiement d'applications ArgoCD

### Atelier Bonus A : Multi-source & ApplicationSet
**Niveau : intermédiaire | ~30 min**

#### Objectif
Gérer plusieurs environnements (dev/staging/prod) avec un seul `ApplicationSet`.

#### Étape 1 : Créer la structure Git

```
apps/
  guestbook/
    base/
      deployment.yaml
      service.yaml
      kustomization.yaml
    overlays/
      dev/
        kustomization.yaml      # replicas: 1, image: :dev
      staging/
        kustomization.yaml      # replicas: 2, image: :staging
      prod/
        kustomization.yaml      # replicas: 3, image: :latest
```

```yaml
# overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../base
patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
    target:
      kind: Deployment
```

#### Étape 2 : Créer l'ApplicationSet

```yaml
# applicationset-guestbook.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook-envs
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
        revision: develop
      - env: staging
        revision: main
      - env: prod
        revision: main
  template:
    metadata:
      name: 'guestbook-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/VOTRE_USERNAME/argocd-example-apps
        targetRevision: '{{revision}}'
        path: 'apps/guestbook/overlays/{{env}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'guestbook-{{env}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

```bash
kubectl apply -f applicationset-guestbook.yaml

# Vérifier les 3 applications créées automatiquement
argocd app list | grep guestbook

# Comparer les ressources entre envs
kubectl get pods -n guestbook-dev
kubectl get pods -n guestbook-staging
kubectl get pods -n guestbook-prod
```

#### Étape 3 : Valider le comportement différencié

```bash
# Vérifier que chaque env a bien le bon nombre de replicas
for env in dev staging prod; do
  echo "=== $env ==="
  kubectl get deployment -n guestbook-$env -o jsonpath='{.items[0].spec.replicas}'
  echo ""
done
```

#### Points de validation
- [ ] 3 applications créées automatiquement par l'ApplicationSet
- [ ] Chaque environnement a le bon nombre de replicas
- [ ] Modifier l'overlay `staging` et observer la sync sélective

---

### Atelier Bonus B : Sync Waves & Resource Hooks
**Niveau : intermédiaire | ~25 min**

#### Objectif
Contrôler précisément l'ordre de déploiement avec les waves et les hooks.

#### Contexte
Vous déployez une app qui nécessite : une migration DB → le backend → le frontend, dans cet ordre strict.

#### Étape 1 : Créer les ressources avec waves

```yaml
# 01-migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  namespace: guestbook
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # avant tout le reste
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: migration
        image: busybox
        command: ['sh', '-c', 'echo "Running migration..." && sleep 5 && echo "Done"']
      restartPolicy: Never
```

```yaml
# 02-backend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: guestbook
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: nginx:alpine
        ports:
        - containerPort: 80
```

```yaml
# 03-frontend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: guestbook
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # après le backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:alpine
```

#### Étape 2 : Observer l'ordre d'exécution

```bash
# Commiter les 3 fichiers, puis :
argocd app sync guestbook --watch

# Dans un autre terminal, observer l'ordre :
kubectl get events -n guestbook --sort-by=.lastTimestamp -w
```

#### Étape 3 : Ajouter un hook PostSync de notification

```yaml
# 04-notify-hook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: notify-deploy
  namespace: guestbook
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: notify
        image: busybox
        command: ['sh', '-c', 'echo "Deployment successful! Notifying team..."']
      restartPolicy: Never
```

#### Points de validation
- [ ] La migration s'exécute en premier (wave -1 / PreSync)
- [ ] Le backend démarre avant le frontend
- [ ] Le hook PostSync se déclenche uniquement après tout le reste
- [ ] Les jobs se suppriment automatiquement (`HookSucceeded`)

---

### Atelier Bonus C : Notifications & monitoring avancé
**Niveau : avancé | ~35 min**

#### Objectif
Configurer ArgoCD Notifications pour alerter sur les événements de sync.

#### Étape 1 : Installer argocd-notifications

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/release-1.2/manifests/install.yaml

# Vérifier l'installation
kubectl get pods -n argocd | grep notifications
```

#### Étape 2 : Configurer un trigger Slack (ou log pour test)

```yaml
# notifications-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # Trigger : notifier en cas d'échec de sync
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]

  # Trigger : notifier quand l'app est Synced
  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-sync-succeeded]

  # Template de notification (log pour test)
  template.app-sync-failed: |
    message: |
      Application {{.app.metadata.name}} sync FAILED.
      Revision: {{.app.status.sync.revision}}
      Error: {{.app.status.operationState.message}}

  template.app-sync-succeeded: |
    message: |
      Application {{.app.metadata.name}} synced successfully.
      Revision: {{.app.status.sync.revision}}
```

```bash
kubectl apply -f notifications-cm.yaml
```

#### Étape 3 : Annoter une application pour activer les notifications

```bash
# Activer les deux triggers sur l'app guestbook
kubectl annotate app guestbook -n argocd \
  notifications.argoproj.io/subscribe.on-sync-failed.log="" \
  notifications.argoproj.io/subscribe.on-sync-succeeded.log=""
```

#### Étape 4 : Déclencher et observer

```bash
# Provoquer un échec de sync : pointer vers un path inexistant
argocd app set guestbook --path nonexistent-path
argocd app sync guestbook

# Observer les logs du controller notifications
kubectl logs -n argocd \
  deployment/argocd-notifications-controller -f

# Corriger le path
argocd app set guestbook --path guestbook
argocd app sync guestbook
# Vous devriez voir la notification de succès dans les logs
```

#### Étape 5 (optionnel) : Webhook vers un endpoint HTTP

```yaml
# Dans le ConfigMap, ajouter :
  service.webhook.my-webhook: |
    url: https://webhook.site/VOTRE_UUID  # Créer un endpoint sur webhook.site
    headers:
    - name: Content-Type
      value: application/json
```

```bash
# Remplacer "log" par "my-webhook" dans les annotations
kubectl annotate app guestbook -n argocd \
  notifications.argoproj.io/subscribe.on-sync-succeeded.my-webhook="" \
  --overwrite
```

#### Points de validation
- [ ] argocd-notifications installé et fonctionnel
- [ ] Notification d'échec visible dans les logs lors d'un sync raté
- [ ] Notification de succès visible après correction
- [ ] (Bonus) Webhook externe reçoit la notification sur webhook.site

