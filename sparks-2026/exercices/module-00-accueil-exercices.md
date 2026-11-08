# Module 00 — Exercices

## Lab 00.1 ⭐ — Vérifier le poste de travail (guidé)
**Durée** : 5 min · **Objectif** : obtenir 0 KO au contrôle du poste
**Contexte** : avant d'installer ArgoCD pour *Hexa Mobilité*, chaque poste doit disposer des outils et des ressources nécessaires.
**Prérequis** : dépôt de la formation cloné, outils installés selon `setup-environnement.md`

### Étapes
1. Se placer dans le dossier des scripts de préparation.
   ```bash
   cd scripts/setup
   ```
2. Lancer le contrôle.
   ```bash
   ./preflight.sh
   ```
   Résultat attendu : dernière ligne `Result: workstation ready`, code retour `0`.
   ```
   OK    CPU: 8 vCPU (min 4)
   OK    RAM available: 9 GB (min 8)
   OK    Container engine: docker
   OK    git: git version 2.43.0
   OK    kind: kind v0.33.0 go1.26.7 linux/amd64
   OK    kubectl: Client Version: v1.36.4
   OK    argocd: argocd: v3.6.1+<COMMIT>
   OK    helm: v4.3.1+<COMMIT>
   OK    kind version v0.33.0
   OK    argocd CLI v3.6.1
   OK    Network: https://raw.githubusercontent.com (HTTP 301)
   OK    Network: https://gitlab.com (HTTP 301)
   OK    Network: https://quay.io/v2/ (HTTP 401)
   OK    Network: https://ghcr.io/v2/ (HTTP 401)
   OK    Network: https://public.ecr.aws (HTTP 308)
   OK    Port 8080 free
   OK    Port 8443 free
   ----
   Result: workstation ready
   ```
3. Pour chaque ligne `KO`, appliquer le déblocage du tableau ci-dessous, puis relancer `./preflight.sh`.

   | Ligne KO | Déblocage |
   |---|---|
   | `Container engine` | Démarrer Docker (`sudo systemctl start docker`) ou Podman |
   | `kind: not installed` | Installer kind v0.33.0 (`setup-environnement.md` § kind) |
   | `Network: <URL> unreachable` | Configurer `HTTPS_PROXY` ou signaler au formateur |
   | `Port 8080 already in use` | Identifier le processus (`ss -ltnp \| grep 8080`) et l'arrêter |

4. Signaler les lignes `WARN` au formateur (versions différentes : souvent sans impact).

### Critères de réussite
- [ ] `./preflight.sh; echo $?` affiche `Result: workstation ready` puis `0`

---

## Exercice 00.2 ⭐⭐ — Préparer les dépôts du fil rouge (semi-autonome)
**Durée** : 10 min · **Objectif** : disposer des deux dépôts GitLab utilisés de J2 à J3
**Contexte** : *Hexa Mobilité* sépare le code applicatif (`flotte-app`) de la configuration de déploiement (`flotte-config`).

**Énoncé** :
- Se connecter à GitLab.com (créer un compte personnel si besoin).
- Créer deux projets **privés** vides avec README : `flotte-app` et `flotte-config`.
- Créer un jeton d'accès personnel (*Personal Access Token*) nommé `formation-argocd`, portée `write_repository`, expiration à J+7.
- Cloner `flotte-config` sur le poste en HTTPS avec ce jeton, puis pousser un commit qui modifie le README.

Variables : `<GITLAB_USER>` = identifiant GitLab ; `<TOKEN>` = jeton créé (ne jamais le committer).

**Indices** :
- Jetons : menu *Edit profile* → *Access tokens* (documentation GitLab : *Personal access tokens*)
- URL de clonage HTTPS avec jeton : `https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git`
- Stocker le jeton dans un gestionnaire de mots de passe : il sera réutilisé au M03 et au M10

**Critères de réussite** :
- [ ] `git ls-remote https://gitlab.com/<GITLAB_USER>/flotte-config.git` demande une authentification (projet privé)
- [ ] `git log --oneline -1` dans `flotte-config` affiche le commit poussé, visible dans l'interface GitLab

---

## Défi 00.3 ⭐⭐⭐ — Précharger les images (autonome)
**Durée** : 10 min · **Objectif** : réduire le temps d'installation du J1 et la charge réseau de la salle
**Contexte** : 10 postes qui téléchargent les mêmes images au même moment saturent la connexion.

**Énoncé** :
- Lancer `scripts/setup/pull-images.sh` et identifier, en lisant le script, la source de la liste des images ArgoCD.
- Expliquer pourquoi une image présente dans le cache Docker du poste n'est pas pour autant disponible dans le nœud `kind`.
- Vérifier, une fois le cluster créé au M02, que les images ArgoCD sont bien présentes dans le nœud.

**Critères de réussite** :
- [ ] `docker images | grep -E 'argocd|dex|redis|podinfo'` liste au moins 6 images
- [ ] Explication correcte du rôle de `kind load docker-image`
- [ ] Commande de vérification dans le nœud fournie (après M02)

---

## Bonus 🚀
Lire le fichier `scripts/setup/versions.env` et proposer une adaptation du `preflight.sh` qui vérifie aussi la version de `kubectl` (écart maximal d'une version mineure avec le cluster, règle de compatibilité Kubernetes).
