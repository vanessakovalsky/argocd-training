# Module 01 — Exercices

## Lab 01.0 ⭐ — Installer la CLI ArgoCD (guidé)
**Durée** : 5 min · **Objectif** : disposer de la CLI `argocd` v3.6.1, d'origine vérifiée
**Contexte** : la CLI sera l'outil principal des équipes d'*Hexa Mobilité* (et de la CI au M10).
**Prérequis** : accès Internet ; CLI déjà présente si le poste a été préparé selon `setup-environnement.md` (passer alors à l'étape 3)

### Étapes
1. Télécharger le binaire et la liste des empreintes de la version v3.6.1 (Linux, processeur x86-64).
   ```bash
   V=v3.6.1
   curl -sSLO https://github.com/argoproj/argo-cd/releases/download/$V/argocd-linux-amd64
   curl -sSLO https://github.com/argoproj/argo-cd/releases/download/$V/cli_checksums.txt
   ```
2. Vérifier l'empreinte, puis installer.
   ```bash
   grep ' argocd-linux-amd64$' cli_checksums.txt | sha256sum -c
   sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
   ```
   Résultat attendu (`Réussi` sur un poste configuré en français) :
   ```
   argocd-linux-amd64: OK
   ```
3. Vérifier la version et parcourir l'aide.
   ```bash
   argocd version --client --short
   argocd --help | head -20
   ```
   Résultat attendu (première ligne) :
   ```
   argocd: v3.6.1+94037c4
   ```

### Critères de réussite
- [ ] Empreinte vérifiée (`OK`)
- [ ] `argocd version --client --short` affiche `v3.6.1`
- [ ] Sous-commandes principales repérées : `login`, `app`, `proj`, `repo`, `cluster`, `account`

---

## Lab 01.1 ⭐ — Push ou pull ? (guidé)
**Durée** : 8 min · **Objectif** : distinguer un déploiement push d'un déploiement GitOps (pull)
**Contexte** : *Hexa Mobilité* recense ses pratiques actuelles avant de passer à ArgoCD.
**Prérequis** : séquence S1.1

### Étapes
1. Pour chaque situation, indiquer **Push** ou **Pull**, puis le principe GitOps respecté ou violé (Déclaratif, Versionné, Tiré, Réconcilié).

   | # | Situation |
   |---|---|
   | 1 | Le job GitLab `deploy` exécute `kubectl apply -f k8s/` avec un kubeconfig stocké en variable CI |
   | 2 | Un agent dans le cluster lit `flotte-config` toutes les 3 minutes et applique les écarts |
   | 3 | Un administrateur lance `helm upgrade flotte-web ./chart` depuis son poste |
   | 4 | Un ops modifie un Deployment avec `kubectl edit` ; 3 minutes plus tard, la modification a disparu |
   | 5 | Jenkins lance `argocd app sync flotte-web` après avoir poussé un nouveau tag d'image dans Git |
   | 6 | Un script cron sur une VM exécute `git pull && kubectl apply -f .` toutes les heures |

2. Comparer les réponses avec le voisin ; noter les situations où le désaccord persiste.

### Critères de réussite
- [ ] 6 situations classées, chacune avec un principe justifié
- [ ] Situation 5 identifiée comme hybride (déclencheur push, déploiement pull)

---

## Exercice 01.2 ⭐⭐ — Reconstituer le cycle d'un déploiement (semi-autonome)
**Durée** : 10 min · **Objectif** : décrire le rôle de chaque composant dans un déploiement
**Contexte** : la version `6.16.0` de `flotte-web` est livrée par un commit dans `flotte-config`.

**Énoncé** :
- Remettre dans l'ordre les 8 étapes suivantes et indiquer pour chacune le composant ArgoCD concerné (ou « hors ArgoCD »).

  | Étape (désordre) |
  |---|
  | A. Le statut passe à `Synced` / `Healthy` dans l'UI |
  | B. Le développeur pousse le commit `image: 6.16.0` |
  | C. Les manifestes rendus sont comparés à l'état du cluster |
  | D. Le dépôt est récupéré (`git fetch`) et les manifestes sont générés |
  | E. Le statut de l'application passe à `OutOfSync` |
  | F. Les ressources modifiées sont appliquées sur le cluster |
  | G. La santé du Deployment est évaluée (pods prêts) |
  | H. Le délai de réconciliation expire (ou un webhook arrive) |

- Préciser quel composant n'a JAMAIS besoin d'accéder à l'API Kubernetes.

**Indices** : schéma « Du commit au déploiement » de la séquence S1.2 ; un composant peut apparaître plusieurs fois.

**Critères de réussite** :
- [ ] Ordre correct (une seule permutation acceptée sur les étapes C / E)
- [ ] Composant correct pour chaque étape
- [ ] `argocd-repo-server` identifié comme sans accès à l'API Kubernetes

---

## Défi 01.3 ⭐⭐⭐ — Lire le manifeste d'installation (autonome)
**Durée** : 10 min · **Objectif** : relier l'architecture théorique au manifeste officiel v3.6.1
**Contexte** : avant l'installation (M02), l'équipe sécurité d'*Hexa Mobilité* demande ce qui sera créé dans le cluster et avec quels droits.

**Énoncé** :
- Télécharger le manifeste officiel `https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml` (aucun cluster nécessaire).
- Lister, à l'aide d'outils en ligne de commande (`grep`, `awk`), les types d'objets créés et leur nombre.
- Identifier les CRD installées, les Deployments / StatefulSets, et le composant qui dispose de droits complets (`*`) sur TOUT le cluster.
- Rédiger en 3 lignes la réponse à l'équipe sécurité : quel risque, quelle justification, quelle mesure possible.

**Critères de réussite** :
- [ ] 3 CRD, 6 Deployments et 1 StatefulSet identifiés
- [ ] `argocd-application-controller` identifié comme seul détenteur de `*` / `*` / `*`
- [ ] Mesure proposée cohérente (projets restreints, installation *namespaced*, comptes de cluster limités)

---

## Bonus 🚀
Lire la page « Principles » du projet OpenGitOps (`opengitops.dev`) et reformuler chaque principe en une ligne appliquée à *Hexa Mobilité* (ex. « Versionné : toute version de `flotte-web` en prod correspond à un commit de `flotte-config` »).
