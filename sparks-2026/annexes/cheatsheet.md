# Aide-mémoire ArgoCD 3.6

## Installation et accès
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml
kubectl port-forward svc/argocd-server -n argocd 8080:443
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
argocd account update-password
kubectl delete secret argocd-initial-admin-secret -n argocd
```

## Contextes et comptes
| Besoin | Commande |
|---|---|
| Lister / changer de contexte | `argocd context` · `argocd context <NOM>` |
| Se connecter sous un nom de contexte | `argocd login <SERVEUR> --username <COMPTE> --insecure --name <NOM>` |
| Comptes | `argocd account list` · `argocd account get --account <COMPTE>` |
| Droits | `argocd account can-i sync applications '<PROJET>/<APP>'` |
| Jeton CI | `argocd account generate-token --account <COMPTE> --expires-in 168h --id <ID>` |
| Valider une politique | `argocd admin settings rbac validate --policy-file argocd-rbac-cm.yaml` |

## Applications
| Besoin | Commande |
|---|---|
| Lister, détailler | `argocd app list` · `argocd app get <APP>` |
| Forcer la comparaison | `argocd app get <APP> --refresh` |
| Écart Git ↔ cluster | `argocd app diff <APP>` · `argocd app diff <APP> --revision <SHA>` |
| Rendu | `argocd app manifests <APP> --source git` |
| Synchroniser, attendre | `argocd app sync <APP>` · `argocd app wait <APP> --sync --health` |
| Historique, retour arrière | `argocd app history <APP>` · `argocd app rollback <APP> <ID>` |
| Arrêter une opération | `argocd app terminate-op <APP>` |
| Journaux, ressources | `argocd app logs <APP> --kind Deployment --name <NOM>` · `argocd app resources <APP>` |
| Actions (Rollout) | `argocd app actions list <APP> --kind Rollout` · `argocd app actions run <APP> resume --kind Rollout --resource-name <NOM>` |
| Supprimer | `argocd app delete <APP> --yes` (`--cascade=false` : ressources conservées) |

## Application déclarative
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flotte-web-dev
  namespace: argocd
  finalizers: [resources-finalizer.argocd.argoproj.io]
spec:
  project: flotte
  source:
    repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git
    targetRevision: main
    path: apps/flotte-web/overlays/dev
  destination: {server: https://kubernetes.default.svc, namespace: flotte-dev}
  syncPolicy:
    automated: {enabled: true, prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true]
```

## Annotations utiles
| Annotation | Effet |
|---|---|
| `argocd.argoproj.io/hook: PreSync` (`Sync`, `PostSync`, `SyncFail`) | Ressource exécutée comme hook |
| `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation` | Cycle de vie du hook (défaut) |
| `argocd.argoproj.io/sync-wave: "-1"` | Ordre d'application |
| `argocd.argoproj.io/sync-options: Prune=false` | Ressource jamais supprimée par prune |
| `argocd.argoproj.io/compare-options: IgnoreExtraneous` | Ressource ignorée dans le statut de synchronisation |
| `notifications.argoproj.io/subscribe.<TRIGGER>.<SERVICE>: ""` | Abonnement à une notification |

## Configuration
| Objet | Contenu | Modification |
|---|---|---|
| `argocd-cm` | URL, comptes, UI, SSO, exclusions | `kubectl patch cm argocd-cm -n argocd --type merge` |
| `argocd-cmd-params-cm` | Paramètres de démarrage | Patch + `kubectl rollout restart` |
| `argocd-rbac-cm` | `policy.csv`, `policy.default`, `scopes` | `kubectl apply --server-side` |
| `argocd-secret` | Mots de passe, secrets SSO et webhook | `kubectl patch secret` |
| Secret étiqueté `argocd.argoproj.io/secret-type: repository` | Dépôt Git ou Helm | `kubectl apply` ou `argocd repo add` |

## RBAC
```text
p, <SUJET>, <RESSOURCE>, <ACTION>, <PROJET>/<OBJET>, allow
g, <UTILISATEUR_OU_GROUPE>, <ROLE>
```
Ressources : `applications`, `applicationsets`, `logs`, `exec`, `projects`, `repositories`, `clusters`, `accounts`. Actions : `get`, `create`, `update`, `delete`, `sync`, `rollback`, `override`, `action/<GROUPE>/<TYPE>/<ACTION>`.

## Argo Rollouts, Kustomize, Sealed Secrets
| Besoin | Commande |
|---|---|
| Suivre un Rollout | `kubectl argo rollouts get rollout <NOM> -n <NS> --watch` |
| Promouvoir, interrompre | `kubectl argo rollouts promote <NOM> -n <NS> --full` · `... abort` |
| Rendu Kustomize | `kubectl kustomize <DOSSIER>` |
| Changer une image | `kustomize edit set image <NOM>=<NOUVEAU_NOM>:<TAG>` |
| Rendu Helm local | `helm template <RELEASE> <CHART> --repo <URL> --version <V> -f <VALEURS>` |
| Sceller un secret | `kubectl create secret generic <NOM> -n <NS> --from-literal=<CLE>=<VALEUR> --dry-run=client -o yaml \| kubeseal --format yaml > sealed-secret.yaml` |
| Sauvegarder ArgoCD | `argocd admin export -n argocd > argocd-backup.yaml` |

## Git pour GitOps
| Besoin | Commande |
|---|---|
| Annuler un commit (retour arrière GitOps) | `git revert --no-edit <SHA>` puis `git push` |
| Version de production | `git tag v1.1.0 && git push origin v1.1.0` |
| Retrouver le commit déployé | `argocd app get <APP>` (révision) puis `git show <SHA>` |
