### Atelier 4.1 : Surveillance et dépannage (60 min)

#### Objectif
Diagnostiquer et résoudre différents types de problèmes de déploiement.

#### Scénario 1 : Application CrashLoopBackOff

**Créer une application défectueuse :**
```yaml
# app-broken.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: broken-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: broken-app
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
```

* Déployer l'application avec kubectl ou argocd

**Modifier pour casser l'application :**
```bash
# Après le déploiement, modifier l'image pour qu'elle n'existe pas
kubectl set image deployment/guestbook-ui guestbook-ui=nonexistent:v1.0.0 -n broken-app
```

**Exercice :**
1. Observer le statut dans ArgoCD UI
2. Identifier que l'app est OutOfSync + Degraded
3. Examiner les logs
4. Corriger le problème via sync

#### Scénario 2 : Ressources insuffisantes

* On revient modifier notre application guestbook

**Créer une app avec requests impossibles :**
```bash
kubectl patch deployment guestbook-ui -n guestbook -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "guestbook-ui",
            "resources": {
              "requests": {
                "memory": "100Gi",
                "cpu": "50"
              }
            }
          }
        ]
      }
    }
  }
}'
```

**Exercice :**
1. Observer les pods Pending
2. Utiliser `kubectl describe pod id du pod -n namespace` pour identifier le problème
3. Utiliser `kubectl top nodes` pour voir les ressources disponibles
4. Corriger les requests dans la commande ci-dessus et repassez la

#### Points de validation
- [ ] Problèmes CrashLoopBackOff identifiés et résolus
- [ ] Problèmes de ressources identifiés
- [ ] Logs consultés correctement
- [ ] Méthodes de diagnostic maîtrisées

---

### Atelier 4.2 : Déploiement Blue-Green (45 min)

#### Objectif
Mettre en place un déploiement blue-green complet.

#### Instructions

**Étape 1 : Préparer le dépôt**

Créer la structure :
```
myapp/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── blue/
    │   └── kustomization.yaml
    └── green/
        └── kustomization.yaml
```
**base/kustomization.yaml**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
```

**base/deployment.yaml :**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: nginx
        image: nginx:1.19
        ports:
        - containerPort: 80
```

**base/service.yaml :**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 80
```

**overlays/blue/kustomization.yaml :**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
nameSuffix: -blue
commonLabels:
  version: blue
images:
- name: nginx
  newTag: "1.19"
```

**overlays/green/kustomization.yaml :**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
nameSuffix: -green
commonLabels:
  version: green
images:
- name: nginx
  newTag: "1.20"  # Version plus récente
```

**Étape 2 : Créer les applications ArgoCD**

```bash
# Créer le namespace
kubectl create namespace bluegreen

# Blue (version actuelle)
argocd app create myapp-blue \
  --repo https://github.com/VOTRE_USERNAME/myapp \
  --path overlays/blue \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace bluegreen \
  --sync-policy automated

# Green (nouvelle version)
argocd app create myapp-green \
  --repo https://github.com/VOTRE_USERNAME/myapp \
  --path overlays/green \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace bluegreen \
  --sync-policy automated
```

**Étape 3 : Déployer et vérifier**

```bash
# Synchroniser les deux
argocd app sync myapp-blue
argocd app sync myapp-green

# Vérifier les pods
kubectl get pods -n bluegreen -l version=blue
kubectl get pods -n bluegreen -l version=green

# Tester blue
kubectl port-forward -n bluegreen svc/blue-myapp 8080:80
curl localhost:8080  # Devrait retourner nginx 1.19

# Tester green
kubectl port-forward -n bluegreen svc/green-myapp 8081:80
curl localhost:8081  # Devrait retourner nginx 1.20
```

**Étape 4 : Basculer le trafic**

```bash
# Initialement, pointer vers blue
kubectl patch service myapp -n bluegreen -p '{"spec":{"selector":{"version":"blue"}}}'

# Tester
kubectl port-forward -n bluegreen svc/myapp 8082:80
curl localhost:8082  # Devrait retourner nginx 1.19

# Basculer vers green
kubectl patch service myapp -n bluegreen -p '{"spec":{"selector":{"version":"green"}}}'

# Tester à nouveau
curl localhost:8082  # Devrait maintenant retourner nginx 1.20

# Rollback si nécessaire
kubectl patch service myapp -n bluegreen -p '{"spec":{"selector":{"version":"blue"}}}'
```

**Étape 5 : Nettoyage**

```bash
# Une fois green validé, supprimer blue
argocd app delete myapp-blue
```

#### Points de validation
- [ ] Deux versions déployées simultanément
- [ ] Trafic basculé de blue vers green
- [ ] Rollback instantané testé
- [ ] Compréhension du processus complet

---

### Atelier 4.3 : Déploiement Canary avec Argo Rollouts (optionnel - 45 min)

#### Objectif
Mettre en place un déploiement canary progressif avec Argo Rollouts.

#### Prérequis

**Installer Argo Rollouts :**
```bash
# Installer le contrôleur Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Installer le plugin kubectl
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# Vérifier
kubectl argo rollouts version
```

#### Instructions

**Étape 1 : Créer un Rollout**

```yaml
# rollout-canary.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: rollout-demo
  namespace: canary-demo
spec:
  replicas: 5
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 1m}
      - setWeight: 40
      - pause: {duration: 1m}
      - setWeight: 60
      - pause: {duration: 1m}
      - setWeight: 80
      - pause: {duration: 1m}
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: rollout-demo
  template:
    metadata:
      labels:
        app: rollout-demo
    spec:
      containers:
      - name: rollout-demo
        image: argoproj/rollouts-demo:blue
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        resources:
          requests:
            memory: 32Mi
            cpu: 5m
---
apiVersion: v1
kind: Service
metadata:
  name: rollout-demo
  namespace: canary-demo
spec:
  ports:
  - port: 80
    targetPort: http
    protocol: TCP
    name: http
  selector:
    app: rollout-demo
```

**Étape 2 : Déployer via ArgoCD**

```bash
# Créer le namespace
kubectl create namespace canary-demo

# Appliquer le rollout
kubectl apply -f rollout-canary.yaml

# Créer l'application ArgoCD
argocd app create rollout-demo \
  --repo https://github.com/VOTRE_USERNAME/rollouts-demo \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace canary-demo \
  --sync-policy automated
```

**Étape 3 : Observer le rollout initial**

```bash
# Voir le statut
kubectl argo rollouts get rollout rollout-demo -n canary-demo

# Dashboard interactif
kubectl argo rollouts dashboard

# Puis ouvrir : http://localhost:3100
```

**Étape 4 : Déclencher un canary deployment**

```bash
# Changer l'image pour déclencher un update
kubectl argo rollouts set image rollout-demo \
  rollout-demo=argoproj/rollouts-demo:yellow \
  -n canary-demo

# Observer le rollout progressif
kubectl argo rollouts get rollout rollout-demo -n canary-demo --watch

# Output attendu :
# NAME                                  KIND        STATUS     AGE
# ⟳ rollout-demo                        Rollout     ॥ Paused   5m
# ├──# revision:2
# │  └──⧉ rollout-demo-789746c88d       ReplicaSet  ✔ Healthy  1m  canary
# │     ├──□ rollout-demo-789746c88d-a  Pod         ✔ Running  1m  ready:1/1
# │     └──□ rollout-demo-789746c88d-b  Pod         ✔ Running  1m  ready:1/1
# └──# revision:1
#    └──⧉ rollout-demo-5747959bdb       ReplicaSet  ✔ Healthy  5m  stable
#       ├──□ rollout-demo-5747959bdb-a  Pod         ✔ Running  5m  ready:1/1
#       ├──□ rollout-demo-5747959bdb-b  Pod         ✔ Running  5m  ready:1/1
#       └──□ rollout-demo-5747959bdb-c  Pod         ✔ Running  5m  ready:1/1
```

**Étape 5 : Interagir avec le rollout**

```bash
# Promouvoir manuellement (passer à l'étape suivante)
kubectl argo rollouts promote rollout-demo -n canary-demo

# Aborter le rollout (rollback)
kubectl argo rollouts abort rollout-demo -n canary-demo

# Retry après un abort
kubectl argo rollouts retry rollout-demo -n canary-demo

# Redémarrer un rollout
kubectl argo rollouts restart rollout-demo -n canary-demo
```

**Étape 6 : Tester avec du trafic**

```bash
# Port-forward vers le service
kubectl port-forward -n canary-demo svc/rollout-demo 8080:80

# Dans un autre terminal, générer du trafic
while true; do curl http://localhost:8080; sleep 0.5; done

# Observer la répartition du trafic entre blue et yellow
```

#### Points de validation
- [ ] Argo Rollouts installé et fonctionnel
- [ ] Rollout créé et déployé
- [ ] Canary deployment progressif observé
- [ ] Promotion manuelle testée
- [ ] Rollback testé
- [ ] Dashboard Argo Rollouts exploré
