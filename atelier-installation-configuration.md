### Atelier 2.1 : Installation complète d'ArgoCD (60 min)

#### Objectif
Installer ArgoCD sur votre cluster Kubernetes et accéder à l'interface web.

#### Instructions

**Étape 1 : Préparation**
```bash
# Vérifier l'accès au cluster
kubectl cluster-info

# Vérifier les ressources disponibles
kubectl top nodes
```

**Étape 2 : Installation**
```bash
# Créer le namespace
kubectl create namespace argocd

# Installer ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que tous les pods soient prêts
kubectl wait --for=condition=available --timeout=300s deployment --all -n argocd
```

**Étape 3 : Vérification**
```bash
# Vérifier les pods
kubectl get pods -n argocd

# Vérifier les services
kubectl get svc -n argocd
```

**Étape 4 : Exposition du service**
```bash
# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**Étape 5 : Récupération du mot de passe**
```bash
# Récupérer le mot de passe initial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

**Étape 6 : Connexion**
```bash
# Via la CLI
argocd login localhost:8080 --username admin --password <password> --insecure

# Via le navigateur
# https://localhost:8080
# Username: admin
# Password: <password>
```

#### Points de validation
- [ ] Tous les pods ArgoCD sont "Running"
- [ ] Le service argocd-server est accessible
- [ ] Connexion réussie via CLI
- [ ] Connexion réussie via UI
- [ ] Mot de passe admin changé

---

### Atelier 2.2 : Configuration des dépôts et RBAC (45 min)

#### Objectif
Configurer ArgoCD avec un dépôt Git et mettre en place des permissions RBAC.

#### Partie 1 : Ajouter des dépôts

**Instructions :**
```bash
# 1. Ajouter le dépôt d'exemples ArgoCD (public)
argocd repo add https://github.com/argoproj/argocd-example-apps

# 2. Ajouter un dépôt Helm (Bitnami)
argocd repo add https://charts.bitnami.com/bitnami \
  --type helm \
  --name bitnami

# 3. Vérifier les dépôts
argocd repo list
```

**Via l'UI :**
1. Aller dans Settings → Repositories
2. Cliquer sur "Connect Repo"
3. Ajouter votre propre dépôt Git (si vous en avez un)

#### Partie 2 : Configurer RBAC

**Créer le fichier `argocd-rbac-cm.yaml` :**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  
  policy.csv: |
    # Deployers peuvent synchroniser
    p, role:deployer, applications, sync, */*, allow
    p, role:deployer, applications, get, */*, allow
    p, role:deployer, applications, override, */*, allow
    
    # Developers ont lecture seule + logs
    p, role:developer, applications, get, */*, allow
    p, role:developer, logs, get, */*, allow
    p, role:developer, projects, get, *, allow
    
    # Admins ont tous les droits
    p, role:admin, *, *, *, allow
```

**Appliquer :**
```bash
kubectl apply -f argocd-rbac-cm.yaml

# Redémarrer ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd
```

#### Partie 3 : Créer des utilisateurs


**Créer le fichier `argocd-user-cm.yaml` :**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  # URL de base d'Argo CD (à adapter si tu utilises un Ingress ou un tunnel)
  url: https://localhost:8080
  # Ajout des comptes utilisateurs 
  accounts.alice: apiKey, login
  accounts.bob: apiKey, login

  # Optionnel : personnalisation du login ArgoCD
  users.anonymous.enabled: "false"

  # Paramètres pour les clusters
  repositories: |
    # Exemple : dépôt Git public
    # - url: https://github.com/argoproj/argocd-example-apps.git
  # Optionnel : gestion du timeout
  timeout.reconciliation: 180s
```
**Appliquer :**
```bash
kubectl apply -f argocd-user-cm.yaml

# Redémarrer ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd
```

* Définir les mots de passe :

```bash
argocd account update-password --account alice --new-password Alice123!
argocd account update-password --account bob --new-password Bob123!
```

**Assigner les rôles :**
```yaml
# Ajouter dans argocd-rbac-cm.yaml
data:
  policy.csv: |
    # ... policies précédentes ...
    
    # Alice est deployer
    g, alice, role:deployer
    
    # Bob est developer
    g, bob, role:developer
```

#### Points de validation
- [ ] Dépôts Git et Helm ajoutés avec succès
- [ ] RBAC configuré
- [ ] Utilisateurs alice et bob créés
- [ ] Alice peut synchroniser une app (on le testera au module 3)
- [ ] Bob ne peut que consulter

---

### Atelier 2.3 : Configuration avancée (optionnel - 30 min)

#### Objectif
Configurer des fonctionnalités avancées : Ingress, TLS, ressources.

#### Partie 1 : Configurer un Ingress

**Créer `argocd-ingress.yaml` :**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.local  # Changez selon votre domaine
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
```

```bash
# Appliquer
kubectl apply -f argocd-ingress.yaml

# Ajouter dans /etc/hosts (sur votre machine locale)
echo "127.0.0.1 argocd.local" | sudo tee -a /etc/hosts

# Accéder : https://argocd.local (si Ingress Controller installé)
```

#### Partie 2 : Ajuster les ressources

```yaml
# argocd-server-resources.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-server
  namespace: argocd
spec:
  template:
    spec:
      containers:
      - name: argocd-server
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

```bash
# Appliquer via patch
kubectl patch deployment argocd-server -n argocd --patch-file argocd-server-resources.yaml
```
