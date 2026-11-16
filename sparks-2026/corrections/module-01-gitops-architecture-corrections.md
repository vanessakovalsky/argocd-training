# Module 01 — Corrections

## Lab 01.0 ⭐ — Installer la CLI ArgoCD
### Solution
Commandes de l'énoncé (testées le 08/11/2026 : empreinte `OK`, `argocd: v3.6.1+94037c4`). Autres systèmes :
- macOS / Linux avec Homebrew : `brew install argocd` (version du dépôt Homebrew, à vérifier avec `argocd version --client`).
- Windows : binaire `argocd-windows-amd64.exe` de la page de la version v3.6.1, renommé `argocd.exe` et placé dans un dossier du `PATH`.
- Processeur ARM : binaire `argocd-linux-arm64` ou `argocd-darwin-arm64`.

### Pourquoi
- Version de la CLI alignée sur le serveur : options et affichages identiques à ceux du support.
- Vérification d'empreinte : garantit que le binaire téléchargé est celui publié par le projet.
- Installation sans `sudo` possible : `install -m 555 argocd-linux-amd64 ~/.local/bin/argocd` (dossier présent dans le `PATH`).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `sha256sum: WARNING: 1 computed checksum did NOT match` | Téléchargement interrompu ou proxy qui modifie le contenu | Retélécharger ; vérifier la taille du fichier |
| `argocd: command not found` | Dossier d'installation absent du `PATH` | `echo $PATH` ; `hash -r` |
| Ancienne version affichée | Autre binaire `argocd` prioritaire dans le `PATH` | `which -a argocd` |
| `curl` renvoie une page HTML de quelques octets | Proxy d'entreprise ou URL erronée | `file argocd-linux-amd64` (doit indiquer `ELF 64-bit`) |

## Lab 01.1 ⭐ — Push ou pull ?
### Solution
| # | Modèle | Principe | Justification |
|---|---|---|---|
| 1 | Push | Tiré : violé | La CI pousse vers le cluster et détient le kubeconfig ; aucune correction ultérieure |
| 2 | Pull | Tiré + Réconcilié : respectés | Agent dans le cluster, boucle de comparaison périodique |
| 3 | Push | Versionné : violé | Déploiement depuis un poste, version déployée non tracée dans Git |
| 4 | Pull | Réconcilié : respecté | Dérive corrigée automatiquement (*self-heal* actif) |
| 5 | Hybride | Tiré : respecté pour le déploiement | Jenkins déclenche seulement ; ArgoCD lit Git et applique. Détient un jeton ArgoCD, pas le kubeconfig |
| 6 | Pull « artisanal » | Réconcilié : partiel | Tire depuis Git, mais sans comparaison, sans détection de dérive entre deux passages, sans suppression des ressources retirées de Git |

### Pourquoi
- Le critère discriminant n'est pas l'outil mais **qui détient les accès au cluster** et **si l'écart est surveillé en continu**.
- Situation 5 : schéma fréquent en entreprise (M10) ; acceptable car le pipeline ne détient qu'un jeton à droits limités sur ArgoCD.
- Situation 6 : « pull » au sens strict, mais ne respecte ni la réconciliation continue (1 h d'écart possible) ni le *prune*.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Situation 5 classée Push | Confusion déclencheur / déploiement | Demander : qui exécute `apply` sur le cluster ? |
| Situation 4 vécue comme un bug | Réconciliation perçue comme une perte de contrôle | Rappeler que Git est la source de vérité ; le correctif doit passer par un commit |
| Situation 6 classée GitOps complet | Seul le sens du flux est regardé | Reprendre les 4 principes un par un |

## Exercice 01.2 ⭐⭐ — Reconstituer le cycle d'un déploiement
### Solution
| Ordre | Étape | Composant |
|---|---|---|
| 1 | B. Le développeur pousse le commit `image: 6.16.0` | Hors ArgoCD (Git) |
| 2 | H. Le délai de réconciliation expire (ou un webhook arrive) | `argocd-application-controller` (ou `argocd-server` qui reçoit le webhook) |
| 3 | D. Le dépôt est récupéré et les manifestes sont générés | `argocd-repo-server` |
| 4 | C. Les manifestes rendus sont comparés à l'état du cluster | `argocd-application-controller` |
| 5 | E. Le statut passe à `OutOfSync` | `argocd-application-controller` |
| 6 | F. Les ressources modifiées sont appliquées | `argocd-application-controller` |
| 7 | G. La santé du Deployment est évaluée | `argocd-application-controller` |
| 8 | A. Le statut `Synced` / `Healthy` s'affiche dans l'UI | `argocd-server` |

Composant sans accès à l'API Kubernetes : `argocd-repo-server` (lit Git, rend les manifestes, les renvoie au contrôleur).

### Pourquoi
- Le contrôleur est le seul composant qui écrit dans le cluster cible : c'est lui qui porte les droits (voir Défi 01.3).
- Isoler le rendu (`repo-server`) protège le cluster : un chart Helm malveillant s'exécute dans un pod sans droits Kubernetes.
- Étape F conditionnée par la politique de synchronisation : en mode manuel, l'application reste `OutOfSync` jusqu'à une action humaine (M05).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `repo-server` placé à l'étape F | Confusion « récupère Git » et « applique » | Revoir le schéma S1.2 : flèche `Ctrl → K8s` uniquement |
| `argocd-server` placé à l'étape C | API server perçu comme moteur | `argocd-server` = façade (UI, API, authentification) |
| Étape G oubliée ou placée avant F | Santé confondue avec synchronisation | Health est calculé APRÈS application, à partir de l'état réel |

### Variantes acceptables
- C et E inversées (comparaison et changement de statut sont quasi simultanés).
- Étape H attribuée à `argocd-server` lorsqu'un webhook est configuré : le serveur reçoit le webhook et demande un rafraîchissement au contrôleur.

## Défi 01.3 ⭐⭐⭐ — Lire le manifeste d'installation
### Solution
```bash
curl -fsSLo install.yaml \
  https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml
grep -E '^kind:' install.yaml | sort | uniq -c
```
Sortie attendue :
```
      3 kind: ClusterRole
      3 kind: ClusterRoleBinding
      7 kind: ConfigMap
      3 kind: CustomResourceDefinition
      6 kind: Deployment
      7 kind: NetworkPolicy
      6 kind: Role
      6 kind: RoleBinding
      2 kind: Secret
      9 kind: Service
      7 kind: ServiceAccount
      1 kind: StatefulSet
```
```bash
# Noms des CRD, Deployments, StatefulSet et ClusterRoles
awk '/^kind:/{k=$2} /^  name:/{print k, $2}' install.yaml \
  | grep -E '^(CustomResourceDefinition|Deployment|StatefulSet|ClusterRole) '
```
Sortie attendue :
```
CustomResourceDefinition applications.argoproj.io
CustomResourceDefinition applicationsets.argoproj.io
CustomResourceDefinition appprojects.argoproj.io
ClusterRole argocd-application-controller
ClusterRole argocd-applicationset-controller
ClusterRole argocd-server
Deployment argocd-applicationset-controller
Deployment argocd-dex-server
Deployment argocd-notifications-controller
Deployment argocd-redis
Deployment argocd-repo-server
Deployment argocd-server
StatefulSet argocd-application-controller
```
```bash
# Règles du ClusterRole du contrôleur
awk '/^kind: ClusterRole$/{f=1} /^---/{f=0} f' install.yaml | sed -n '1,18p'
```
Sortie attendue (extrait) :
```
  name: argocd-application-controller
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
```

Réponse type à l'équipe sécurité :
- Risque : `argocd-application-controller` dispose de tous les droits sur tout le cluster ; sa compromission = compromission du cluster.
- Justification : il doit pouvoir créer n'importe quel type de ressource décrit dans Git (y compris CRD et ressources cluster).
- Mesures : AppProjects limitant ressources et namespaces autorisés (M03), installation *namespaced* (`namespace-install.yaml`) quand ArgoCD ne gère que quelques namespaces, comptes de service à droits réduits sur les clusters distants (M12).

### Pourquoi
- Les 7 NetworkPolicy du manifeste restreignent déjà les flux entrants vers chaque composant (défense en profondeur).
- `argocd-server` a aussi un ClusterRole (`get`, `patch`, `delete` sur toutes les ressources, lecture des journaux des pods : actions lancées depuis l'UI) : droits larges, sans création (`create`).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Comptage faux de `kind: Deployment` | `grep kind` sans ancrage `^` (lignes imbriquées comptées) | Utiliser `^kind:` |
| `curl: (22) The requested URL returned error: 404` | Faute dans le tag (`3.6.1` sans `v`) | Les tags ArgoCD commencent par `v` |
| Aucune sortie avec `awk` | Fins de ligne Windows (`\r`) après copier-coller | `sed -i 's/\r$//' install.yaml` |

## Bonus
Reformulation type pour *Hexa Mobilité* :
- Déclaratif : `flotte-config` décrit le Deployment `flotte-web` avec 2 réplicas, pas les commandes pour le créer.
- Versionné et immuable : toute version en production correspond à un commit de `flotte-config`, revu en merge request.
- Tiré automatiquement : ArgoCD, dans le cluster, lit `flotte-config` ; la CI n'a aucun accès au cluster.
- Réconcilié en continu : un `kubectl edit` en production est détecté en moins de 3 minutes, signalé ou annulé.

## QCM — Réponses
1. **D** — La réconciliation continue compare Git et cluster en boucle et corrige l'écart (si self-heal actif).
2. **B** — En pull, l'agent est dans le cluster ; aucun identifiant du cluster n'est exposé à l'extérieur.
3. **C** — `argocd-repo-server` clone le dépôt et rend les manifestes (YAML, Helm, Kustomize).
4. **A** — Seul `argocd-application-controller` applique les ressources sur les clusters cibles.
5. **C** — Sync et Health sont indépendants : Git est appliqué mais les pods échouent (image, configuration).
6. **B** — `timeout.reconciliation` vaut 120 s par défaut, avec un jitter jusqu'à 60 s.
7. **C** — L'`AppProject` restreint dépôts sources, destinations et types de ressources.
8. **B** — Depuis la 3.0, le suivi par annotation (`argocd.argoproj.io/tracking-id`) est le défaut.
