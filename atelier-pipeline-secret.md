
### Atelier 5.1 : Intégration CI/CD complète (60 min)

#### Objectif
Créer un pipeline CI/CD complet avec GitHub Actions et ArgoCD.

#### Prérequis
- Compte GitHub
- Cluster Kubernetes avec ArgoCD installé
- Registry Docker (Docker Hub ou GitHub Container Registry)

#### Instructions

**Étape 1 : Préparer les dépôts**

```bash
# Dépôt application (code source)
mkdir myapp && cd myapp
git init

# Structure du projet
cat > app.py <<EOF
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello from ArgoCD v1.0!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

cat > Dockerfile <<EOF
FROM python:3.11-slim
WORKDIR /app
RUN pip install flask
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
EOF

cat > requirements.txt <<EOF
flask==3.0.0
EOF

# Créer le workflow GitHub Actions
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml <<'EOF'
name: Build and Deploy

on:
  push:
    branches: [ main ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Log in to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Build and push
      uses: docker/build-push-action@v4
      with:
        context: .
        push: true
        tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
    
    - name: Update manifests
      env:
        CD_REPO_TOKEN: ${{ secrets.CD_REPO_TOKEN }}
      run: |
        git clone https://x-access-token:${CD_REPO_TOKEN}@github.com/${{ github.repository }}-cd.git cd-repo
        cd cd-repo
        sed -i "s|image:.*|image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}|" k8s/deployment.yaml
        git config user.name "GitHub Actions"
        git config user.email "actions@github.com"
        git add .
        git commit -m "Update image to ${{ github.sha }}"
        git push
EOF

git add .
git commit -m "Initial commit"
# Créer le dépôt sur GitHub et push
```

**Étape 2 : Créer le dépôt CD (manifestes K8s)**

```bash
# Dépôt CD séparé
mkdir myapp-cd && cd myapp-cd
git init

mkdir k8s
cat > k8s/deployment.yaml <<EOF
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
      - name: myapp
        image: ghcr.io/<VOTRE_USERNAME>/myapp:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
EOF

git add .
git commit -m "Initial manifests"
# Créer le dépôt sur GitHub et push
```

**Étape 3 : Créer l'application ArgoCD**

```bash
argocd app create myapp \
  --repo https://github.com/<VOTRE_USERNAME>/myapp-cd \
  --path k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

**Étape 4 : Tester le pipeline**

* Vous devez générer un PAT (menu Mon compte > Settings > Developper settings) avec les droits en lecture et en écriture sur le repository myapp-cd, copier le token généré
* Sur le dépôt myapp, dans les paramètres du dépôt ajouté un secret nommé CD_REPO_TOKEN et collé la valeur du token généré
* Ces deux étapes sont nécessaires pour que le pipeline de CI de github action puisse modifier votre manifeste et déclencher votre déploiement sur argocd.

```bash
# Modifier l'application
cd myapp
sed -i 's/v1.0/v2.0/' app.py
git add .
git commit -m "Update to v2.0"
git push

# Observer :
# 1. GitHub Actions build l'image
# 2. GitHub Actions met à jour le dépôt CD
# 3. ArgoCD détecte le changement et sync
# 4. Application déployée avec la nouvelle version
```

#### Points de validation
- [ ] Pipeline CI construit et publie l'image
- [ ] Dépôt CD mis à jour automatiquement
- [ ] ArgoCD déploie la nouvelle version
- [ ] Application accessible avec la nouvelle version

---

### Atelier 5.2 : Gestion des secrets avec Sealed Secrets (45 min)

#### Objectif
Mettre en place Sealed Secrets pour gérer les secrets de manière sécurisée dans Git.

#### Instructions

**Étape 1 : Installer Sealed Secrets**

```bash
# Installer le controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Attendre que le controller soit prêt
kubectl wait --for=condition=available --timeout=300s \
  deployment sealed-secrets-controller -n kube-system

# Installer kubeseal CLI
KUBESEAL_VERSION='0.24.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

**Étape 2 : Créer et sceller un secret**

```bash
# Créer un secret standard
kubectl create secret generic app-secrets \
  --from-literal=db-password=supersecret123 \
  --from-literal=api-key=myapikey456 \
  --namespace default \
  --dry-run=client \
  -o yaml > secret.yaml

# Sceller le secret
kubeseal -f secret.yaml -w sealed-secret.yaml \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system

# Afficher le secret scellé
cat sealed-secret.yaml
```

**Étape 3 : Ajouter à Git et déployer via ArgoCD**

```bash
# Dans votre dépôt CD
cp sealed-secret.yaml myapp-cd/k8s/

cd myapp-cd
git add k8s/sealed-secret.yaml
git commit -m "Add sealed secret"
git push

# ArgoCD va synchroniser et le controller va déchiffrer le secret
```

**Étape 4 : Utiliser le secret dans l'application**

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: db-password
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: api-key
```

* Commit et push du fichier de déploiement
* Créer votre application et vérifier que le pod s'est bien lancer avec le secret

**Étape 5 : Rotation des secrets**

```bash
# Pour mettre à jour un secret
kubectl create secret generic app-secrets \
  --from-literal=db-password=newsecret789 \
  --from-literal=api-key=newkey012 \
  --namespace default \
  --dry-run=client \
  -o yaml | \
kubeseal -w sealed-secret-new.yaml

# Remplacer l'ancien
mv sealed-secret-new.yaml myapp-cd/k8s/sealed-secret.yaml
git add k8s/sealed-secret.yaml
git commit -m "Rotate secrets"
git push
```

#### Points de validation
- [ ] Sealed Secrets controller installé
- [ ] Secret créé et scellé
- [ ] Secret scellé commité dans Git (sécurisé)
- [ ] ArgoCD déploie le sealed secret
- [ ] Application accède au secret déchiffré
- [ ] Rotation de secret testée

---

### Atelier 5.3 : Optimisation des performances (optionnel - 30 min)

#### Objectif
Optimiser ArgoCD pour gérer un grand nombre d'applications.

#### Instructions

**Étape 1 : Activer le sharding**

```bash
# Éditer le StatefulSet du controller
kubectl edit statefulset argocd-application-controller -n argocd

# Modifier :
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: argocd-application-controller
        env:
        - name: ARGOCD_CONTROLLER_REPLICAS
          value: "3"
```

**Étape 2 : Augmenter les ressources**

```bash
kubectl patch deployment argocd-repo-server -n argocd --type json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {"memory": "512Mi", "cpu": "250m"},
      "limits": {"memory": "1Gi", "cpu": "1000m"}
    }
  }
]'
```

**Étape 3 : Configurer le cache**

```yaml
# Dans argocd-cm
data:
  # Cache des dépôts
  repository.credentials: |
    # Cache TTL
    timeout.reconciliation: 180s
```

**Étape 4 : Monitoring**

```bash
# Voir les métriques
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082

# Accéder aux métriques
curl http://localhost:8082/metrics | grep argocd_app
```

#### Points de validation
- [ ] Sharding activé avec 3 réplicas
- [ ] Ressources augmentées
- [ ] Métriques accessibles
- [ ] Performance améliorée (temps de réconciliation réduit)

---
