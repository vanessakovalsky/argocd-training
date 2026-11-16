# Module 02 — Corrections

## Lab 02.1 ⭐ — Créer le cluster et installer ArgoCD
### Solution
```bash
kind create cluster --config scripts/setup/kind-config.yaml
kubectl get nodes
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=600s
kubectl rollout status statefulset/argocd-application-controller -n argocd
kubectl get pods -n argocd
kubectl get crd | grep argoproj
```
Sortie attendue (dernière commande) :
```
applications.argoproj.io      2026-11-08T11:55:21Z
applicationsets.argoproj.io   2026-11-08T11:55:22Z
appprojects.argoproj.io       2026-11-08T11:55:22Z
```
Script équivalent (idempotent) : `scripts/m02/labs/install-argocd.sh`. Durée mesurée : environ 35 s après création du cluster, images préchargées.

Fichier `scripts/setup/kind-config.yaml` :
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: argocd-formation
nodes:
  - role: control-plane
    image: kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
    extraPortMappings:
      - containerPort: 30443
        hostPort: 8443
        protocol: TCP
```

### Pourquoi
- Image du nœud figée par version ET empreinte (`@sha256`) : recommandation des notes de version kind, cluster identique sur tous les postes.
- Kubernetes v1.36.4 : version testée par ArgoCD 3.6 (1.34 à 1.37), une version mineure en dessous de la plus récente.
- `kubectl wait` plutôt qu'observation manuelle : condition vérifiable, réutilisable dans un script.
- `rollout status` pour le contrôleur : un StatefulSet n'expose pas la condition `Available` des Deployments.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `metadata.annotations: Too long: may not be more than 262144 bytes` | `kubectl apply` sans `--server-side` (syntaxe 2.x) | Relancer avec `--server-side --force-conflicts` |
| `failed to bind host port 0.0.0.0:8443/tcp: address already in use` | Port 8443 occupé sur le poste | Libérer le port, ou changer `hostPort` dans `kind-config.yaml` (et l'URL de l'exercice 02.3) |
| `error getting credentials` puis `no usernames for https://index.docker.io/v1/` | Docker Desktop : `credsStore: desktop` sans session Docker Hub | Connexion à Docker Hub (`docker login`) ou retrait de la ligne `credsStore` de `~/.docker/config.json` (après accord du stagiaire) |
| Pods `ImagePullBackOff` | Proxy, limite de téléchargement d'un registre | `kubectl describe pod` ; `pull-images.sh` sur un réseau ouvert puis `kind load` |
| `The connection to the server 127.0.0.1:<PORT> was refused` | Docker redémarré ou mis en veille | Attendre le redémarrage du conteneur nœud (`docker ps`), puis `kind export kubeconfig --name argocd-formation` |
| `kubectl wait` expire | Poste sous-dimensionné (RAM) | `kubectl get pods -n argocd` + `kubectl describe pod` ; fermer les applications lourdes |

## Lab 02.2 ⭐ — Accéder à l'UI et à la CLI
### Solution
Commandes de l'énoncé, dans l'ordre. Mot de passe `<ADMIN_PASSWORD>` conservé pour toute la formation (scripts de rattrapage : variable `ARGOCD_ADMIN_PASSWORD`).

Contrôle de l'ancien mot de passe :
```bash
argocd login localhost:8080 --username admin --password '<ANCIEN_MOT_DE_PASSE>' --insecure
```
Sortie attendue :
```
{"level":"fatal","msg":"rpc error: code = Unauthenticated desc = Invalid username or password","time":"<DATE>"}
```

### Pourquoi
- Port-forward vers le port 443 du service, qui cible le port 8080 du conteneur : `argocd-server` sert UI, API REST et gRPC sur ce même port, en TLS auto-signé.
- `argocd admin initial-password` lit le secret `argocd-initial-admin-secret` via le kubeconfig : aucun accès à l'API ArgoCD requis.
- Secret initial supprimé : il contient le mot de passe en clair et n'a plus d'usage après le changement (documentation *Getting Started*).
- Cluster `in-cluster` en statut `Unknown` : normal tant qu'aucune application ne le cible (cluster non surveillé).
- `guestbook` : `OutOfSync` / `Missing` à la création (sync manuelle par défaut), puis `Synced` / `Healthy`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `WARNING: server is not configured with TLS` puis `EOF` | Port local déjà utilisé par un autre service non TLS (le port-forward a échoué) | `ss -ltnp \| grep 8080` ; port-forward sur un port libre (ex. `18080:443`) |
| `tls: first record does not look like a TLS handshake` | Contexte CLI pointant vers un ancien serveur (`~/.config/argocd/config`) | `argocd context` puis `argocd login` sur la bonne adresse |
| `error: lost connection to pod` | Port-forward interrompu (veille, redémarrage du pod) | Relancer le port-forward ; solution durable : exercice 02.3 |
| Navigateur : `NET::ERR_CERT_AUTHORITY_INVALID` | Certificat auto-signé | Accepter l'exception (lab uniquement) |
| `argocd app sync` : `permission denied` | Session expirée | `argocd relogin` |

## Exercice 02.3 ⭐⭐ — Exposer l'UI sans port-forward
### Solution
```bash
kubectl patch svc argocd-server -n argocd --type merge -p '{"spec":{"type":"NodePort",
  "ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080},
  {"name":"https","port":443,"protocol":"TCP","targetPort":8080,"nodePort":30443}]}}'
kubectl get svc argocd-server -n argocd
curl -sk https://localhost:8443/healthz; echo
argocd login localhost:8443 --username admin --insecure
```
Sortie attendue :
```
service/argocd-server patched
NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
argocd-server   NodePort   10.96.106.222   <none>        80:30080/TCP,443:30443/TCP   92s
ok
'admin:login' logged in successfully
Context 'localhost:8443' updated
```
Arrêt du port-forward : `Ctrl+C` dans son terminal. État final du module : `scripts/m02/catch-up/m02-final-state.sh`.

### Pourquoi
- Patch `merge` : la liste `ports` est remplacée entièrement, d'où la redéfinition des deux ports.
- NodePort fixé (30443) : plage par défaut 30000-32767 ; valeur fixe nécessaire pour le `extraPortMappings` de kind.
- Mapping de port défini à la CRÉATION du cluster : impossible à ajouter ensuite sans recréer le cluster.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `curl: (7) Failed to connect to localhost port 8443` | Cluster créé sans `kind-config.yaml` (aucun mapping) | Recréer le cluster avec la configuration (`m02-final-state.sh`) |
| `provided port is already allocated` | NodePort 30443 déjà utilisé par un autre service | `kubectl get svc -A \| grep 30443` |
| Port 80 disparu du service | Patch avec le seul port 443 | Patch avec les deux ports, ou `kubectl edit` |

### Variantes acceptables
- `kubectl edit svc argocd-server -n argocd` : modification interactive, même résultat.
- Patch JSON (`--type json`) ciblant `/spec/type` et `/spec/ports/1/nodePort` : plus précis, plus fragile (dépend de l'ordre des ports).

## Défi 02.4 ⭐⭐⭐ — Installation reproductible avec Kustomize
### Solution
`argocd-install/kustomization.yaml` :
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml
patches:
  - path: argocd-server-nodeport.yaml
```
`argocd-install/argocd-server-nodeport.yaml` :
```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
spec:
  type: NodePort
  ports:
    - name: https
      port: 443
      targetPort: 8080
      nodePort: 30443
```
```bash
kubectl kustomize argocd-install/ | grep -B2 -A14 'name: argocd-server$' | grep -E 'type:|nodePort'
kubectl apply -k argocd-install/ --server-side --force-conflicts
```
Sortie attendue (extrait) :
```
  type: NodePort
service/argocd-server serverside-applied
```

### Pourquoi
- Patch stratégique (*strategic merge*) : fusion des ports par numéro de port, le port 80 du manifeste est conservé (NodePort attribué automatiquement).
- Montée de version : seule l'URL `v3.6.1` → `v3.6.2` change ; les personnalisations restent séparées et relues en merge request.
- Base du *self-managed* (M12) : ce dossier, poussé dans Git, peut être déployé par ArgoCD lui-même.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `accumulating resources` suivi d'une erreur HTTP 404 | Faute dans l'URL ou le tag | Copier l'URL du Lab 02.1 |
| Les deux ports remplacés par le seul port 443 | Patch JSON 6902 au lieu d'un patch stratégique | Patch stratégique (fichier YAML partiel, sans `op:`) |
| Erreur de taille d'annotation | `kubectl apply -k` sans `--server-side` | Ajouter `--server-side --force-conflicts` |

### Variantes acceptables
- Chart Helm `argo/argo-cd` (version 10.15.0, appVersion v3.6.1) avec `server.service.type: NodePort` (`server.service.nodePortHttps` vaut 30443 par défaut).
- Ressource distante remplacée par une copie locale de `install.yaml` (fonctionne hors ligne, mise à jour moins simple).

## Bonus
```bash
kubectl config set-context --current --namespace=argocd
argocd login --core
argocd app list
argocd context localhost:8443
kubectl config set-context --current --namespace=default
```
- Sans le changement de namespace : erreur `configmap "argocd-cm" not found` (le mode core lit les ressources ArgoCD dans le namespace courant du kubeconfig).
- Mode core : authentification et autorisation = celles du kubeconfig (RBAC Kubernetes) ; le RBAC ArgoCD (`argocd-rbac-cm`) et les comptes ArgoCD ne s'appliquent pas.

## QCM — Réponses
1. **B** — La CRD `ApplicationSet` dépasse 262 Ko, taille maximale de l'annotation `last-applied-configuration` de l'apply client.
2. **C** — `ha/install.yaml` : réplicas multiples, Redis HA, anti-affinité exigeant au moins 3 nœuds.
3. **B** — Le secret `argocd-initial-admin-secret`, à supprimer après changement du mot de passe.
4. **C** — Le contrôleur est un StatefulSet (nom de pod suffixé `-0`), pour permettre le sharding.
5. **C** — Ingress ou Gateway API avec certificat reconnu : nom DNS stable, TLS valide, pas de tunnel.
6. **B** — `--insecure` désactive la vérification du certificat TLS, auto-signé en lab.
7. **B** — Sans synchronisation, les ressources n'existent pas encore : `OutOfSync` / `Missing`.
