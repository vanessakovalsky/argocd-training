# Préparation de l'environnement — Formation ArgoCD

Environnement de chaque stagiaire : un cluster Kubernetes `kind` sur son propre poste. Aucune ressource cloud, aucun coût.
Versions relevées le 08/11/2026 sur les dépôts officiels ; source unique : `scripts/setup/versions.env`.

## 1. Poste de travail

| Élément | Exigence | Contrôle |
|---|---|---|
| Système | Linux x86-64 (Ubuntu 22.04 ou plus récent conseillé) ; macOS et Windows (WSL 2) : voir § 6 | `uname -sm` |
| Processeur | 4 vCPU minimum | `nproc` |
| Mémoire | 8 Go **disponibles** (16 Go installés conseillés) | `free -g` |
| Disque | 20 Go libres (images) | `df -h ~` |
| Moteur de conteneurs | Docker 25 ou plus récent (testé : 25.0.3) ; Podman possible, non testé (§ 6) | `docker info` |
| Droits | Utilisateur membre du groupe `docker` | `id -nG` |
| Réseau | Accès HTTPS à `github.com`, `raw.githubusercontent.com`, `ghcr.io`, `quay.io`, `public.ecr.aws`, `docker.io`, `registry.k8s.io`, `get.helm.sh`, `dl.k8s.io`, `gitlab.com`, `registry.gitlab.com`, `stefanprodan.github.io` | `scripts/setup/preflight.sh` |
| Ports libres | 8080 (port-forward) et 8443 (accès NodePort) | `ss -ltn` |

> ⚠️ **Docker Desktop** : la ligne `"credsStore": "desktop"` de `~/.docker/config.json` peut empêcher le téléchargement des images publiques sans session Docker Hub (`error getting credentials`). Se connecter (`docker login`) ou retirer cette ligne.
> ⚠️ **Mémoire** : prévoir au moins 8 Go alloués à Docker Desktop ; en dessous, le moteur peut s'arrêter pendant les modules J3 (constaté pendant la préparation du support).

## 2. Outils en ligne de commande

| Outil | Version | Usage |
|---|---|---|
| `kind` | v0.33.0 | Cluster local |
| `kubectl` | v1.36.6 | Administration Kubernetes |
| `argocd` | v3.6.1 | CLI ArgoCD |
| `helm` | v4.3.1 | Rendu local de charts (M09) |
| `kubectl-argo-rollouts` | v1.10.2 | Bleu-vert et canari (M08) |
| `kubeseal` | 0.41.2 | Secrets scellés (M11) |
| `git` | 2.30 ou plus récent | Dépôts du fil rouge |
| `curl` | toute version récente | Tests HTTP |

### Installation automatique (Linux x86-64)
```bash
git clone <URL_DEPOT_FORMATION> formation-argocd
cd formation-argocd
./scripts/setup/install-tools.sh            # installe dans ~/.local/bin
echo $PATH | tr ':' '\n' | grep -x "$HOME/.local/bin"
```
Sortie attendue (fin) :
```
kind installed
kubectl installed
argocd installed
helm installed
kubectl-argo-rollouts installed
kubeseal installed
Tools installed in /home/<UTILISATEUR>/.local/bin
```
Le script vérifie l'empreinte SHA-256 de chaque fichier téléchargé (fichiers d'empreintes publiés par chaque projet) et ignore un outil déjà présent dans la bonne version. Dossier `~/.local/bin` absent du `PATH` : ajouter `export PATH="$HOME/.local/bin:$PATH"` à `~/.bashrc`.

### Installation manuelle (exemple : CLI ArgoCD)
```bash
V=v3.6.1
curl -sSLO https://github.com/argoproj/argo-cd/releases/download/$V/argocd-linux-amd64
curl -sSLO https://github.com/argoproj/argo-cd/releases/download/$V/cli_checksums.txt
grep ' argocd-linux-amd64$' cli_checksums.txt | sha256sum -c
install -m 0755 argocd-linux-amd64 ~/.local/bin/argocd
```
Même principe pour les autres outils : URL et fichiers d'empreintes visibles dans `scripts/setup/install-tools.sh`.

## 3. Comptes et dépôts

| Élément | Action | Quand |
|---|---|---|
| Compte GitLab.com | Créer un compte personnel ; valider le compte si GitLab le demande pour les runners partagés (téléphone ou carte) | J-7 |
| Projet `flotte-config` | Projet privé avec README (Exercice 00.2) | J-7 ou M00 |
| Projet `flotte-app` | Projet avec README ; passé en public au M10 (registre d'images) | J-7 ou M00 |
| Jeton personnel | `formation-argocd`, portée `write_repository`, expiration fin de formation + 7 jours | M00 |

## 4. Vérification du poste
```bash
./scripts/setup/preflight.sh; echo "exit=$?"
```
Résultat attendu : dernière ligne `Result: workstation ready`, `exit=0`. Chaque ligne `KO` indique le point à corriger (déblocages : corrections du module 00, Lab 00.1).

Préchargement des images (conseillé, réseau de salle partagé) :
```bash
./scripts/setup/pull-images.sh
```

## 5. Cluster et rattrapage

| Étape | Script | Durée |
|---|---|---|
| Cluster + ArgoCD (M02) | `scripts/m02/labs/install-argocd.sh` | 2 à 4 min |
| État final d'un module | `scripts/mXX/catch-up/mXX-final-state.sh` (variables en tête de chaque script) | 1 à 4 min |

Variables communes des scripts de rattrapage à partir du M04 :
```bash
export ARGOCD_ADMIN_PASSWORD='<ADMIN_PASSWORD>'
export FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git
export FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git
```
M03 : `GITLAB_USER`, `GITLAB_DEPLOY_USER`, `GITLAB_DEPLOY_TOKEN` (jeton de déploiement de `flotte-config`, portée `read_repository`). Le M10 n'a pas de script automatique (pipeline lié au projet GitLab du stagiaire) : voir ses corrections.

## 6. Autres systèmes
Labs testés sur Linux avec Docker. macOS, Windows et Podman : procédures issues des documentations officielles, non rejouées → `scripts/setup/preflight.sh` obligatoire à J-7 sur ces postes ; Podman déconseillé pour la session (support expérimental de kind).


| Système | Adaptation |
|---|---|
| macOS (Apple Silicon) | Docker Desktop ; binaires `darwin-arm64` des mêmes versions, ou `brew install kind kubernetes-cli argocd helm kubeseal argoproj/tap/kubectl-argo-rollouts` (Homebrew le 08/11/2026 : kind 0.33.0, argocd 3.6.1, helm 4.3.1, kubeseal 0.41.2 ; kubectl 1.37.2, compatible à ± 1 version mineure avec le nœud 1.36) |
| Windows | WSL 2 (Ubuntu) + Docker Desktop avec intégration WSL activée pour la distribution ; procédure Linux dans WSL |
| Podman | Support expérimental de kind (Podman 3.0 ou plus, cgroup v2, mode rootless avec réglages systemd) : `export KIND_EXPERIMENTAL_PROVIDER=podman` avant `kind create cluster` ; images par `podman save` + `kind load image-archive` |

## 7. Nettoyage après la formation

| Ressource | Commande | Délai incompressible |
|---|---|---|
| Cluster `kind` | `./scripts/m02/cleanup/delete-cluster.sh` | Aucun |
| Images locales | `docker image prune -a` (après accord) | Aucun |
| Outils | `rm ~/.local/bin/{kind,kubectl,argocd,helm,kubectl-argo-rollouts,kubeseal}` | Aucun |
| Jetons GitLab | Révoquer `formation-argocd` et les jetons de déploiement | Aucun |
| Projets GitLab | Conserver (révision) ou supprimer (page du projet → menu *Actions* ⋮ → *Delete*) | GitLab.com : projet en attente de suppression 30 jours ; *Delete permanently* sur le projet en attente pour une suppression immédiate |
