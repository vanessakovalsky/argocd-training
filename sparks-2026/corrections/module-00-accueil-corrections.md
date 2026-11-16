# Module 00 — Corrections

## Lab 00.1 ⭐ — Vérifier le poste de travail
### Solution
```bash
cd scripts/setup
./preflight.sh; echo "exit=$?"
```
Sortie attendue : `Result: workstation ready` puis `exit=0`. Les numéros de version de `git` et de Go (ligne `kind`) varient selon le poste et sont sans impact.

### Pourquoi
- Code retour = nombre de `KO` : exploitable dans une boucle ou un script de préparation de salle.
- Les `WARN` signalent une version différente de celle de référence (`versions.env`) sans bloquer : une CLI `argocd` v3.5 fonctionne avec un serveur v3.6, mais certains affichages peuvent différer.
- Codes HTTP 301 / 308 / 401 = service joignable (redirection ou authentification demandée) ; seul `000` signale un échec réseau.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `Container engine: neither docker nor podman responds` alors que Docker est installé | Utilisateur absent du groupe `docker` | `sudo usermod -aG docker $USER` puis nouvelle session |
| `RAM available` en KO sur un poste de 16 Go | Navigateur et IDE ouverts | Fermer les applications lourdes, relancer |
| Tous les contrôles réseau en KO | Proxy d'entreprise non configuré | `export HTTPS_PROXY=http://<PROXY>:<PORT>` (et dans la configuration Docker) |
| `Port 8080 already in use` | Autre service local (Jenkins, serveur de développement) | `ss -ltnp \| grep 8080`, arrêt du processus, ou port alternatif au M02 |
| Podman détecté mais `kind` échoue au M02 | Fournisseur Podman non activé | `export KIND_EXPERIMENTAL_PROVIDER=podman` |

## Exercice 00.2 ⭐⭐ — Préparer les dépôts du fil rouge
### Solution
1. GitLab.com → *New project* → *Create blank project* : `flotte-app`, visibilité *Private*, case *Initialize repository with a README* cochée. Même opération pour `flotte-config`.
2. Avatar → *Edit profile* → *Access tokens* → *Add new token* : nom `formation-argocd`, date d'expiration J+7, portée `write_repository`.
3. Clonage et premier commit :
   ```bash
   export GITLAB_USER=<GITLAB_USER>
   export GITLAB_TOKEN=<TOKEN>
   git clone "https://oauth2:${GITLAB_TOKEN}@gitlab.com/${GITLAB_USER}/flotte-config.git"
   cd flotte-config
   echo "Configuration de déploiement Hexa Mobilité" >> README.md
   git commit -am "docs: description du dépôt"
   git push
   ```
   Sortie attendue (fin) :
   ```
   To https://gitlab.com/<GITLAB_USER>/flotte-config.git
      a1b2c3d..e4f5a6b  main -> main
   ```

### Pourquoi
- Deux dépôts = séparation code / configuration : un changement de configuration ne relance pas la CI applicative, et l'historique de déploiement reste lisible (bonne pratique recommandée par la documentation ArgoCD).
- Projets privés : obligent à configurer des identifiants de dépôt dans ArgoCD au M03 (cas réel en entreprise).
- `write_repository` suffit pour pousser ; ArgoCD n'aura besoin que d'un accès en lecture (jeton de déploiement au M03, moindre privilège).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `remote: HTTP Basic: Access denied` | Jeton expiré, mal copié ou portée `read_repository` seule | Recréer le jeton avec `write_repository` |
| `fatal: repository not found` | Faute de frappe dans `<GITLAB_USER>` ou projet créé dans un groupe | Copier l'URL depuis le bouton *Code* du projet |
| Jeton visible dans `git remote -v` | Jeton inclus dans l'URL de clonage | Acceptable pour la formation ; en entreprise : `git credential` ou clé SSH |
| Branche `master` au lieu de `main` | Réglage par défaut du compte | Conserver le nom affiché et l'utiliser dans tous les labs |

### Variantes acceptables
- Clé SSH ajoutée au profil GitLab et clonage `git@gitlab.com:<GITLAB_USER>/flotte-config.git` (plus sûr, mais configuration ArgoCD SSH à prévoir au M03).
- Projets créés dans un groupe GitLab personnel (`<GROUPE>/flotte-app`) : adapter toutes les URL des labs.

## Défi 00.3 ⭐⭐⭐ — Précharger les images
### Solution
```bash
cd scripts/setup
./pull-images.sh
docker images | grep -E 'argocd|dex|redis|podinfo'
```
Sortie attendue (versions au 08/11/2026) :
```
quay.io/argoproj/argocd                  v3.6.1         <IMAGE_ID>
ghcr.io/dexidp/dex                       v2.46.0        <IMAGE_ID>
public.ecr.aws/docker/library/redis      8.10.1-alpine  <IMAGE_ID>
ghcr.io/stefanprodan/podinfo             6.17.0         <IMAGE_ID>
ghcr.io/stefanprodan/podinfo             6.16.0         <IMAGE_ID>
ghcr.io/stefanprodan/podinfo             6.15.0         <IMAGE_ID>
```
Les colonnes ID, date et taille varient (`<IMAGE_ID>` et colonnes suivantes omises).

- Source de la liste : le manifeste officiel `manifests/install.yaml` de la version `ARGOCD_VERSION`, lu en ligne et filtré sur les lignes `image:` ; aucune version d'image n'est écrite en dur.
- Cache poste ≠ nœud kind : le nœud kind est lui-même un conteneur qui exécute son propre runtime (`containerd`) avec son propre stockage d'images. `kind load docker-image` copie l'image du cache Docker vers ce runtime ; le script le fait automatiquement si le cluster `argocd-formation` existe déjà.
- Vérification dans le nœud (après M02) :
  ```bash
  docker exec argocd-formation-control-plane crictl images | grep argocd
  ```
  Sortie attendue :
  ```
  quay.io/argoproj/argocd   v3.6.1   <IMAGE_ID>   <TAILLE>
  ```

### Pourquoi
- Sans préchargement : 10 postes × environ 0,8 Go d'images téléchargés pendant le M02 (mesuré le 08/11/2026, taille compressée amd64 : nœud kind 384 Mo, ArgoCD 228 Mo, Dex 50 Mo, Redis 39 Mo, podinfo 3 × 35 Mo), installation ralentie de plusieurs minutes ; Argo Rollouts et Sealed Secrets téléchargés en plus au M08 et au M11.
- Script idempotent : relançable sans effet de bord (les images déjà présentes ne sont pas retéléchargées).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `toomanyrequests` | Limite de téléchargement d'un registre | Relancer plus tard ; images ArgoCD hébergées hors Docker Hub (quay.io, ghcr.io, ECR public) |
| `kind load` ignoré | Cluster pas encore créé | Relancer le script après le M02 |
| Podman : `kind load docker-image` échoue | Commande prévue pour Docker | `podman save -o img.tar <IMAGE>` puis `kind load image-archive img.tar --name argocd-formation` (documentation kind) ; Podman hors périmètre testé (§ 6 de `setup-environnement.md`) |

## Bonus
Ajout possible en fin de section 3 de `preflight.sh` (cluster nécessaire : contrôle à relancer après le M02) :
```bash
if kubectl version -o json >/dev/null 2>&1; then
  c=$(kubectl version -o json | sed -n 's/.*"minor": *"\([0-9]*\).*/\1/p' | head -1)
  s=$(kubectl version -o json | sed -n 's/.*"minor": *"\([0-9]*\).*/\1/p' | tail -1)
  d=$((c - s)); [ "${d#-}" -le 1 ] && ok "kubectl skew: client 1.$c / server 1.$s" \
    || ko "kubectl skew: client 1.$c / server 1.$s (max 1 minor)"
fi
```
Règle appliquée : politique de compatibilité de versions de Kubernetes, `kubectl` supporté à ± 1 version mineure de l'API server.

## QCM — Réponses
1. **B** — `-A` (`--all-namespaces`) liste les pods de tous les namespaces ; sans option, seul le namespace courant est affiché.
2. **C** — Le Deployment gère un ReplicaSet qui maintient le nombre de réplicas demandé.
3. **B** — `git revert` crée un commit inverse sans réécrire l'historique : geste clé du rollback GitOps (M06).
4. **B** — La CI construit, teste et publie l'artefact (image) ; en GitOps, le déploiement est délégué à ArgoCD.
5. **A** — Helm package les manifestes en charts paramétrables par `values.yaml` (vu au M09).
6. **B** — GitOps : l'état souhaité est déclaré dans Git et un agent (ArgoCD) l'applique et le maintient en continu.
