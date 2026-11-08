# flotte-app

Code et pipeline de construction de l'image `flotte-web` (Hexa Mobilité, fil rouge de la formation ArgoCD).

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image construite à partir de podinfo 6.17.0 |
| `.gitlab-ci.yml` | Construction, publication dans le registre GitLab, mise à jour de `flotte-config` |
| `ci/update-config.sh` | Mise à jour du tag d'image de l'overlay `dev` (`kustomize edit set image`) |
| `Jenkinsfile` | Équivalent Jenkins (démonstration) |

Le pipeline n'accède jamais au cluster : ArgoCD détecte le nouveau commit de `flotte-config` et déploie.
