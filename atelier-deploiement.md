### Atelier 3.1 : Déployer votre première application
#### Pré-requis

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
