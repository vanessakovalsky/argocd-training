## Atelier final : Projet complet (90 min)

### Objectif
Mettre en place une plateforme GitOps complète pour une application multi-tiers.

### Contexte
Vous devez déployer une application e-commerce avec :
- Frontend (React)
- Backend API (Node.js)
- Base de données (PostgreSQL)
- Cache (Redis)
- Ingress avec TLS
- Monitoring (Prometheus + Grafana)

### Architecture cible

```
┌─────────────────────────────────────────────────────┐
│                   Users / Internet                  │
└───────────────────┬─────────────────────────────────┘
                    │
        ┌───────────▼───────────┐
        │  Ingress (TLS)        │
        │  shop.example.com     │
        └───────────┬───────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
    ┌───▼────┐            ┌────▼───┐
    │Frontend│            │Backend │
    │ React  │────────────│ Node.js│
    └────────┘            └────┬───┘
                               │
                     ┌─────────┴─────────┐
                     │                   │
                 ┌───▼────┐         ┌───▼───┐
                 │  Redis │         │Postgre│
                 │  Cache │         │  SQL  │
                 └────────┘         └───────┘
```

### Instructions

#### Étape 1 : Préparation de la structure GitOps (15 min)

```bash
# Créer la structure de dépôt
mkdir ecommerce-gitops && cd ecommerce-gitops
git init

# Structure
mkdir -p {base,overlays/{dev,staging,production},infrastructure}

# Base manifests
cat > base/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- namespace.yaml
- postgresql.yaml
- redis.yaml
- backend.yaml
- frontend.yaml
- ingress.yaml

commonLabels:
  app.kubernetes.io/name: ecommerce
  app.kubernetes.io/managed-by: argocd
EOF
```

#### Étape 2 : Créer les manifestes de base (20 min)

```yaml
# base/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce

---
# base/postgresql.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: ecommerce
spec:
  ports:
  - port: 5432
  selector:
    app: postgresql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
  namespace: ecommerce
spec:
  serviceName: postgresql
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:15
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: ecommerce
        - name: POSTGRES_USER
          value: shop_user
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi

---
# base/redis.yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ecommerce
spec:
  ports:
  - port: 6379
  selector:
    app: redis
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
# base/backend.yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: ecommerce
spec:
  ports:
  - port: 3000
    targetPort: 3000
  selector:
    app: backend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        version: v1
    spec:
      containers:
      - name: backend
        image: myregistry/ecommerce-backend:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          value: postgresql://shop_user:$(DB_PASSWORD)@postgresql:5432/ecommerce
        - name: REDIS_URL
          value: redis://redis:6379
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: password
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"

---
# base/frontend.yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: ecommerce
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: frontend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        version: v1
    spec:
      containers:
      - name: frontend
        image: myregistry/ecommerce-frontend:latest
        ports:
        - containerPort: 80
        env:
        - name: REACT_APP_API_URL
          value: http://backend:3000
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
# base/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-ingress
  namespace: ecommerce
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - shop.example.com
    secretName: ecommerce-tls
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 3000
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
```

#### Étape 3 : Créer les overlays par environnement (15 min)

```yaml
# overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ecommerce-dev

resources:
- ../../base

namePrefix: dev-

commonLabels:
  environment: dev

replicas:
- name: backend
  count: 1
- name: frontend
  count: 1

images:
- name: myregistry/ecommerce-backend
  newTag: develop-latest
- name: myregistry/ecommerce-frontend
  newTag: develop-latest

patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/resources/requests/memory
      value: "128Mi"
  target:
    kind: Deployment
    name: backend

secretGenerator:
- name: postgresql-secret
  literals:
  - password=devpassword123

---
# overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ecommerce-staging

resources:
- ../../base

namePrefix: staging-

commonLabels:
  environment: staging

replicas:
- name: backend
  count: 2
- name: frontend
  count: 2

images:
- name: myregistry/ecommerce-backend
  newTag: staging-v1.2.0
- name: myregistry/ecommerce-frontend
  newTag: staging-v1.2.0

secretGenerator:
- name: postgresql-secret
  literals:
  - password=stagingpassword456

---
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ecommerce-prod

resources:
- ../../base
- hpa.yaml
- pdb.yaml
- servicemonitor.yaml

namePrefix: prod-

commonLabels:
  environment: production

replicas:
- name: backend
  count: 5
- name: frontend
  count: 3
- name: redis
  count: 2

images:
- name: myregistry/ecommerce-backend
  newTag: v1.2.0
- name: myregistry/ecommerce-frontend
  newTag: v1.2.0

patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/resources/requests/memory
      value: "512Mi"
    - op: replace
      path: /spec/template/spec/containers/0/resources/requests/cpu
      value: "500m"
  target:
    kind: Deployment
    name: backend

# Secret externe (géré via Sealed Secrets ou External Secrets)
# secretGenerator commenté car géré ailleurs
```

**Production specifics:**

```yaml
# overlays/production/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
  namespace: ecommerce-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: prod-backend
  minReplicas: 5
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
  namespace: ecommerce-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: prod-frontend
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70

---
# overlays/production/pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
  namespace: ecommerce-prod
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: backend
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: ecommerce-prod
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: frontend

---
# overlays/production/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-metrics
  namespace: ecommerce-prod
spec:
  selector:
    matchLabels:
      app: backend
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

#### Étape 4 : Créer les applications ArgoCD (15 min)

```yaml
# argocd-apps/ecommerce-dev.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ecommerce-dev
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: ecommerce
  source:
    repoURL: https://github.com/myorg/ecommerce-gitops
    targetRevision: HEAD
    path: overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: ecommerce-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

---
# argocd-apps/ecommerce-staging.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ecommerce-staging
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: ecommerce
  source:
    repoURL: https://github.com/myorg/ecommerce-gitops
    targetRevision: HEAD
    path: overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: ecommerce-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true

---
# argocd-apps/ecommerce-prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ecommerce-prod
  namespace: argocd
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: prod-deployments
    notifications.argoproj.io/subscribe.on-health-degraded.slack: prod-alerts
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: ecommerce
  source:
    repoURL: https://github.com/myorg/ecommerce-gitops
    targetRevision: v1.2.0  # Tag Git pour production
    path: overlays/production
  destination:
    server: https://prod-cluster.example.com
    namespace: ecommerce-prod
  syncPolicy:
    # Sync manuel en production
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  # Ignore differences pour HPA
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
```

**Ou utiliser un ApplicationSet:**

```yaml
# argocd-apps/ecommerce-appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: ecommerce
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
        cluster: in-cluster
        autoSync: "true"
        revision: HEAD
      - env: staging
        cluster: in-cluster
        autoSync: "true"
        revision: HEAD
      - env: production
        cluster: prod-cluster
        autoSync: "false"
        revision: v1.2.0
  
  template:
    metadata:
      name: 'ecommerce-{{env}}'
      labels:
        environment: '{{env}}'
    spec:
      project: ecommerce
      source:
        repoURL: https://github.com/myorg/ecommerce-gitops
        targetRevision: '{{revision}}'
        path: overlays/{{env}}
      destination:
        server: '{{cluster}}'
        namespace: 'ecommerce-{{env}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

#### Étape 5 : Créer le projet ArgoCD (10 min)

```yaml
# argocd-apps/project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ecommerce
  namespace: argocd
spec:
  description: E-commerce application platform
  
  sourceRepos:
  - https://github.com/myorg/ecommerce-gitops
  - https://charts.bitnami.com/bitnami
  
  destinations:
  - namespace: 'ecommerce-*'
    server: '*'
  
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
  
  # Deny dangerous resources
  namespaceResourceBlacklist:
  - group: ''
    kind: ResourceQuota
  
  roles:
  - name: developer
    description: Developers - read only
    policies:
    - p, proj:ecommerce:developer, applications, get, ecommerce/*, allow
    - p, proj:ecommerce:developer, logs, get, ecommerce/*, allow
    groups:
    - ecommerce-dev-team
  
  - name: operator
    description: Operators - can sync
    policies:
    - p, proj:ecommerce:operator, applications, *, ecommerce/ecommerce-dev, allow
    - p, proj:ecommerce:operator, applications, *, ecommerce/ecommerce-staging, allow
    - p, proj:ecommerce:operator, applications, get, ecommerce/ecommerce-prod, allow
    - p, proj:ecommerce:operator, applications, sync, ecommerce/ecommerce-prod, allow
    groups:
    - ecommerce-ops-team
  
  syncWindows:
  # Production: sync autorisé uniquement la nuit
  - kind: deny
    schedule: '0 6-22 * * *'
    duration: 16h
    applications:
    - ecommerce-prod
    manualSync: true
```

#### Étape 6 : Déployer et valider (15 min)

```bash
# 1. Créer le projet
kubectl apply -f argocd-apps/project.yaml

# 2. Créer les applications
kubectl apply -f argocd-apps/

# 3. Vérifier les applications
argocd app list

# 4. Synchroniser dev
argocd app sync ecommerce-dev

# 5. Vérifier la santé
argocd app get ecommerce-dev

# 6. Voir les ressources
kubectl get all -n ecommerce-dev

# 7. Tester l'application
kubectl port-forward -n ecommerce-dev svc/frontend 8080:80

# 8. Vérifier les logs
kubectl logs -n ecommerce-dev deployment/backend --tail=50

# 9. Synchroniser staging
argocd app sync ecommerce-staging

# 10. Production (manuel)
argocd app sync ecommerce-prod
```

#### Étape 7 : Tests et scenarios (10 min)

**Scénario 1 : Mise à jour de version**
```bash
# Modifier l'image tag dans overlays/dev/kustomization.yaml
cd overlays/dev
kustomize edit set image myregistry/ecommerce-backend:develop-abc123

# Commit et push
git add .
git commit -m "Update backend to abc123"
git push

# Observer la synchronisation automatique
argocd app get ecommerce-dev --watch
```

**Scénario 2 : Rollback**
```bash
# Voir l'historique
argocd app history ecommerce-dev

# Rollback vers la version précédente
argocd app rollback ecommerce-dev 1

# Ou via Git
git revert HEAD
git push
```

**Scénario 3 : Dérive manuelle**
```bash
# Modifier une ressource manuellement
kubectl scale deployment backend -n ecommerce-dev --replicas=10

# Observer le self-heal
argocd app get ecommerce-dev
# Devrait revenir à la valeur dans Git (1 replica pour dev)
```

**Scénario 4 : Promotion vers production**
```bash
# 1. Tag la version validée en staging
git tag -a v1.3.0 -m "Release 1.3.0"
git push --tags

# 2. Mettre à jour production
# Éditer argocd-apps/ecommerce-prod.yaml
# targetRevision: v1.3.0

git add argocd-apps/ecommerce-prod.yaml
git commit -m "Promote v1.3.0 to production"
git push

# 3. Synchroniser manuellement (production)
argocd app sync ecommerce-prod

# 4. Monitorer
argocd app wait ecommerce-prod --health --timeout 300
```

### Points de validation finale

- [ ] Structure GitOps complète créée
- [ ] Manifestes Kubernetes pour tous les composants
- [ ] Overlays pour dev, staging, production
- [ ] Applications ArgoCD configurées
- [ ] Projet ArgoCD avec RBAC
- [ ] Synchronisation automatique (dev/staging)
- [ ] Synchronisation manuelle (production)
- [ ] HPA et PDB en production
- [ ] Rollback testé
- [ ] Self-heal vérifié
- [ ] Promotion dev → staging → prod testée


Voici l'atelier bonus :

---

# Atelier bonus — Monitoring ArgoCD avec Prometheus & Grafana

**Durée estimée : 25 min | Prérequis : ArgoCD installé sur Minikube**---

## Étape 1 — Installer Prometheus & Grafana via Helm (5 min)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123 \
  --wait
```

Vérifie que tout est up :

```bash
kubectl get pods -n monitoring
```

---

## Étape 2 — Configurer le scraping des pods ArgoCD (5 min)

Prometheus doit savoir où scraper. Crée un `PodMonitor` qui cible les 3 replicas du controller :

```yaml
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: argocd-controller
  namespace: monitoring
  labels:
    release: monitoring
spec:
  namespaceSelector:
    matchNames:
      - argocd
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-application-controller
  podMetricsEndpoints:
    - port: metrics
      interval: 15s
      path: /metrics
EOF
```

Le label `release: monitoring` est important — il permet au Prometheus opéré par kube-prometheus-stack de découvrir ce `PodMonitor`.

Vérifie que Prometheus a bien détecté les targets (attends ~30s) :

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# Ouvre http://localhost:9090/targets
# Tu dois voir 3 targets argocd-controller UP
```

---

## Étape 3 — Importer le dashboard Grafana (5 min)

ArgoCD fournit un dashboard officiel sur Grafana.com (ID `14584`).

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &
```

Ouvre `http://localhost:3000` → login `admin` / `admin123`

Puis : **Dashboards → Import → ID `14584` → Load → Datasource : Prometheus → Import**

---

## Étape 4 — Vérifier les métriques clés (5 min)

Dans le dashboard ou via PromQL directement sur `http://localhost:9090` :

```promql
# Nombre d'apps par état de santé
argocd_app_info{health_status="Healthy"}

# Apps en erreur de sync
argocd_app_info{sync_status="OutOfSync"}

# Durée moyenne de reconciliation par shard
rate(argocd_app_reconcile_duration_seconds_sum[5m])
/ rate(argocd_app_reconcile_duration_seconds_count[5m])

# Nombre de syncs par app sur les 5 dernières minutes
rate(argocd_app_sync_total[5m])
```

---

## Étape 5 — Cleanup (1 min)

```bash
pkill -f "port-forward"
helm uninstall monitoring -n monitoring
kubectl delete podmonitor argocd-controller -n monitoring
kubectl delete namespace monitoring
```

---

**Ce que tu as mis en place :

** Prometheus scrape les 3 pods du controller indépendamment (ce qui résout le problème de sharding vu précédemment), et Grafana agrège tout dans un dashboard unique avec les métriques `argocd_app_*` consolidées sur l'ensemble du cluster.
