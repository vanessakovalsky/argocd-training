# Fichiers du module 05

| Fichier | Destination dans `flotte-config` | Lab |
|---|---|---|
| `flotte-web-dev-auto.yaml` | `argocd/flotte-web-dev.yaml` (état final : auto-sync, prune, self-heal) | 05.1 à 05.3 |
| `hook-presync-migration.yaml` | `apps/flotte-web/` | 05.4 |
| `hook-postsync-smoke-test.yaml` | `apps/flotte-web/` | 05.4 |

ConfigMap en vague -1 : annotation `argocd.argoproj.io/sync-wave: "-1"` ajoutée à `apps/flotte-web/configmap.yaml` (Lab 05.4).
