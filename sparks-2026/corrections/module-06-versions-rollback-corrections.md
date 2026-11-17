# Module 06 — Corrections

Script d'état final du module (testé sur v3.6.1) — mêmes variables que le M04 :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m06/catch-up/m06-final-state.sh
```
État obtenu : `flotte-web` en `6.16.0` dans Git et dans le cluster, synchronisation automatique active, contrôle RBAC distinct du rollback activé.

## Lab 06.1 ⭐ — Livrer une version fautive et lire l'historique
### Solution
Historique observé (testé, extrait) :
```
ID      DATE                           REVISION
8       2026-11-08 13:58:58 +0100 CET  main (c0dcb75)
9       2026-11-08 14:01:13 +0100 CET  main (4ee1140)
```
Diff avec la révision précédente, cluster en `6.17.0` (sens déduit du test inverse, cluster en `6.16.0`) :
```
<   PODINFO_UI_MESSAGE: Hexa Mobilite - v6.17 (anomalie)
>   PODINFO_UI_MESSAGE: Hexa Mobilite - suivi de flotte
<         image: ghcr.io/stefanprodan/podinfo:6.17.0
>         image: ghcr.io/stefanprodan/podinfo:6.16.0
```
Lignes `<` : cluster ; lignes `>` : révision demandée.

### Pourquoi
- Une entrée d'historique par synchronisation réussie, y compris les synchronisations automatiques et les rollbacks.
- `--revision` accepte un hash de commit, une branche ou un tag : comparaison possible avec n'importe quelle version, même absente de l'historique.
- `sed -E 's#(podinfo:)[0-9.]+#\16.17.0#'` : remplacement indépendant de la version de départ.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Aucune nouvelle entrée d'historique | Synchronisation pas encore déclenchée | `--refresh`, puis `app wait` |
| Message inchangé dans l'application | Seule la ConfigMap a changé (voir Bonus) | Image et configuration dans le même commit |
| `unable to resolve revision` | Hash tronqué inexistant ou faute de frappe | `git log --oneline` |

## Lab 06.2 ⭐ — Rollback GitOps par `git revert`
### Solution
```bash
git revert --no-edit HEAD && git push
argocd app get flotte-web-dev --refresh > /dev/null
argocd app wait flotte-web-dev --sync --health
```
Résultat (testé) : image `ghcr.io/stefanprodan/podinfo:6.16.0`, message `Hexa Mobilite - suivi de flotte`, entrée d'historique `main (<SHA_DU_REVERT>)`.

### Pourquoi
- Le revert est un commit : relu, tracé, visible dans GitLab ; aucune divergence entre Git et le cluster.
- Hooks rejoués : la migration (PreSync) et le smoke test (PostSync) s'exécutent aussi lors d'un retour arrière ; une migration non réversible doit être prévue (script de retour ou compatibilité ascendante du schéma).
- Pods recréés : l'image change, donc le message de la ConfigMap restaurée est relu au démarrage.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Conflit pendant `git revert` | Commits postérieurs sur les mêmes lignes | Résoudre, `git revert --continue` |
| `git push` refusé (`non-fast-forward`) | Clone local en retard | `git pull --rebase`, puis push |
| Revert du mauvais commit | `HEAD` n'est pas le commit fautif | `git revert <SHA>` explicite |

## Exercice 06.3 ⭐⭐ — Rollback d'urgence
### Solution
```bash
# 1. Relivraison de la 6.17.0 (annulation du revert)
git revert --no-edit HEAD && git push
argocd app get flotte-web-dev --refresh > /dev/null && argocd app wait flotte-web-dev --sync --health
# 2. Urgence : suspension de l'automatisme, rollback
kubectl patch app flotte-web-dev -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"enabled":false}}}}'
argocd app history flotte-web-dev
argocd app rollback flotte-web-dev <ID_DERNIERE_VERSION_SAINE>
argocd app get flotte-web-dev | grep -E "Sync Policy|Sync Status"
```
Sortie attendue (testée) :
```
Sync Policy:        Manual
Sync Status:        OutOfSync from main (<SHA_VERSION_FAUTIVE>)
```
```bash
# 3. Réalignement de Git, puis réactivation dans le fichier versionné
git revert --no-edit HEAD && git push
sed -i 's/enabled: false/enabled: true/' argocd/flotte-web-dev.yaml   # si modifié dans le fichier
kubectl apply -f argocd/flotte-web-dev.yaml
argocd app get flotte-web-dev --refresh | grep -E "Sync Policy|Sync Status"
```
Sortie attendue (testée) :
```
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (<SHA_DU_REVERT>)
```

### Pourquoi
- `Manual` : `automated.enabled: false` désactive l'automatisme en gardant `prune` et `selfHeal`.
- `OutOfSync` : le cluster exécute une révision antérieure, Git contient toujours la version fautive ; c'est l'état attendu pendant l'urgence.
- Le rollback crée une entrée d'historique (même révision qu'une entrée antérieure).
- `kubectl apply` du fichier versionné à la fin : le `kubectl patch` d'urgence ne doit pas rester la seule trace de l'état de l'Application.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Version fautive revenue juste après le rollback | Automatisme réactivé avant le revert | Recommencer : suspension, rollback, revert, PUIS réactivation |
| `rollback cannot be initiated when auto-sync is enabled` | `enabled: false` non pris en compte | `argocd app get` : vérifier `Sync Policy: Manual` |
| `application has no history with id` | ID inexistant ou purgé (`revisionHistoryLimit`) | `argocd app history` |

### Variantes acceptables
- `argocd app set flotte-web-dev --sync-policy none` pour suspendre (supprime tout le bloc `automated` ; réglages à restaurer depuis le fichier).
- Rollback depuis l'UI : *History and rollback* → menu de l'entrée → *Rollback*.

## Défi 06.4 ⭐⭐⭐ — Réserver le rollback aux ops
### Solution
```bash
argocd account can-i rollback applications 'flotte/flotte-web-dev' --argocd-context alice
kubectl patch cm argocd-cm -n argocd --type merge \
  -p '{"data":{"server.rbac.rollback.enforce.enable":"true"}}'
argocd login localhost:8443 --username dev-alice --insecure --name alice
argocd account can-i rollback applications 'flotte/flotte-web-dev' --argocd-context alice
argocd app rollback flotte-web-dev <ID> --argocd-context alice
```
Sorties attendues (testées) : `yes`, puis `no`, puis :
```
{"level":"fatal","msg":"rpc error: code = PermissionDenied desc = permission denied","time":"<DATE>"}
```
`ops-bob` (`role:admin`) : autorisé, la politique intégrée `role:admin` contient `applications, rollback, */*`.

Historique limité :
```bash
kubectl patch app flotte-web-dev -n argocd --type merge -p '{"spec":{"revisionHistoryLimit":5}}'
```
Constat (testé) : l'historique n'est tronqué qu'à la synchronisation suivante (nouvelle entrée), pas immédiatement. En production : `revisionHistoryLimit` dans le fichier `argocd/flotte-web-dev.yaml`.

### Pourquoi
- Par défaut (rétrocompatibilité), un rollback est contrôlé par la permission `sync` (code source v3.6.1 : `rbac.ActionSync` si l'option est désactivée).
- Option activée : contrôle de l'action `rollback`, que `role:dev` n'accorde pas.
- Rôle dédié possible pour des devs seniors : `p, role:ops-release, applications, rollback, flotte/*, allow`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `can-i` toujours `yes` | Option non activée ou valeur non chaîne (`true` sans guillemets) | `"true"` |
| `invalid session` après le patch | Session expirée | `argocd login` à nouveau |

## Défi 06.5 ⭐⭐⭐ — Gel des déploiements et dérogation d'urgence
Testé sur un cluster kind séparé (ArgoCD 3.6.1).

### Solution
```bash
argocd proj windows add flotte --kind deny --schedule "0 0 * * *" --duration 24h \
  --applications '*' --manual-sync
argocd proj windows list flotte
```
Sortie mesurée :
```
ID  STATUS  KIND  SCHEDULE   DURATION  APPLICATIONS  NAMESPACES  CLUSTERS  MANUALSYNC  SYNCOVERRUN  TIMEZONE  USEANDOPERATOR
0   Active  deny  0 0 * * *  24h       *             -           -         Enabled     Disabled     UTC       Disabled
```
Après le push de `6.17.0` : image toujours en `6.16.0`, `argocd app get flotte-web-dev` →
```
SyncWindow:         Manual Allowed
Assigned Windows:   deny:0 0 * * *:24h
Sync Status:        OutOfSync from main (<SHA>)
```
`argocd app sync flotte-web-dev` → `Phase: Succeeded`, image `6.17.0`.

Sans dérogation :
```bash
argocd proj windows disable-manual-sync flotte 0
argocd app sync flotte-web-dev
```
```
rpc error: code = PermissionDenied desc = cannot sync: blocked by sync window
```
Fin du gel : `argocd proj windows delete flotte 0` → changement en attente déployé au rafraîchissement suivant.

Version déclarative (AppProject) :
```yaml
spec:
  syncWindows:
    - kind: deny
      schedule: "0 0 * * *"
      duration: 24h
      applications: ["*"]
      manualSync: true
      timeZone: Europe/Paris
```

### Pourquoi
- Fenêtre `deny` : bloque les synchronisations automatiques (et le self-heal) des applications ciblées ; `manualSync: true` = dérogation, tracée dans l'historique et soumise au RBAC `sync`.
- `0 0 * * *` + `24h` : fenêtre couvrant la journée entière → active dès la création (exercice) ; en réel, `schedule` et `duration` décrivent la période de clôture.
- Fenêtre `allow` : seules les périodes listées autorisent la synchronisation (créneaux de mise en production, M12).
- `timeZone` : sans précision, UTC → décalage d'une à deux heures en France.
- Rattrapage automatique à la fin du gel : l'écart Git/cluster a été conservé, aucun commit perdu.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Fenêtre `Inactive` | Horaire hors période, ou fuseau UTC | `--time-zone Europe/Paris`, vérifier `STATUS` |
| Le commit part quand même | Application non ciblée (`--applications` trop étroit) | `Assigned Windows` dans `argocd app get` |
| Self-heal inactif pendant le gel | Comportement normal d'une fenêtre `deny` | Le rappeler aux équipes : une dérive manuelle n'est plus corrigée |

## Défi 06.6 ⭐⭐⭐ — Promotion par tag mobile : pratique ou piège ?
Testé sur un cluster kind séparé (ArgoCD 3.6.1, dépôt Git interne au cluster).

### Solution
```bash
# v1.0.0 = image 6.16.0 (commit courant)
git tag -a v1.0.0 -m "flotte-web 6.16.0" && git tag prod && git push origin main --tags
kubectl apply -f argocd/flotte-web-prod.yaml      # targetRevision: prod, namespace flotte-prod
# v1.1.0 = image 6.17.0
sed -i 's/6.16.0/6.17.0/' apps/flotte-web/deployment.yaml
git commit -am "release: flotte-web 6.17.0" && git tag -a v1.1.0 -m "flotte-web 6.17.0"
git push origin main v1.1.0
# Promotion
git tag -f prod && git push -f origin prod
argocd app get flotte-web-prod --refresh
# Rollback
git tag -f prod 'v1.0.0^{}' && git push -f origin prod
argocd app get flotte-web-prod --refresh
```
Mesures :

| Étape | Sans `--refresh` (30 s) | Avec `--refresh` |
|---|---|---|
| `prod` → `v1.1.0` | `6.16.0` (inchangé) | `6.17.0` |
| `prod` → `v1.0.0` | — | `6.16.0` |

`argocd app history flotte-web-prod` :
```
ID  DATE                           REVISION
0   2026-11-16 16:46:45 +0100 CET  prod (e9f7898)
1   2026-11-16 16:47:41 +0100 CET  prod (0adcfd2)
2   2026-11-16 16:47:57 +0100 CET  prod (e9f7898)
```
`git log` : aucun commit pour la promotion ni pour le rollback.

Nettoyage : `kubectl delete -f argocd/flotte-web-prod.yaml`, `kubectl delete namespace flotte-prod`, `git push origin :refs/tags/prod && git tag -d prod`.

### Pourquoi
- Délai : la résolution du tag suit le cycle de rafraîchissement (≤ 3 min, cache du repo-server) ; un webhook GitLab d'événement *tag push* le raccourcit.
- Trace : seul l'historique ArgoCD (limité par `revisionHistoryLimit`) et le journal du serveur Git conservent les déplacements ; `git log` ne montre rien → audit fragile, aucune revue possible.
- `git push -f` sur un tag : droit de réécriture à accorder (tags non protégés dans GitLab) → surface de risque.
- Alternative recommandée : tags de version immuables (`v1.1.0`, protégés dans GitLab) + promotion par commit ou merge request qui change `targetRevision` (ou la version dans le fichier d'environnement) → revue, approbation, rollback par `git revert`, historique complet.
- Tag mobile acceptable : environnement de démonstration, ou fichier de promotion géré par un outil (Kargo, ArgoCD Image Updater en mode *git write-back*).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `! [rejected] prod -> prod (already exists)` | Push sans `-f` | `git push -f origin prod` |
| Le tag `prod` pointe sur l'objet tag et non le commit | `git tag -f prod v1.0.0` sur un tag annoté (fonctionne, mais crée un tag de tag) | `v1.0.0^{}` |
| Aucun changement après promotion | Cache de résolution | `argocd app get <APP> --refresh` |

## Bonus
Testé : ConfigMap mise à jour (`Hexa Mobilite - suivi de flotte (bonus)`), application inchangée (`"message": "Hexa Mobilite - suivi de flotte"`). Les variables issues d'une ConfigMap (`envFrom`) sont lues au démarrage du conteneur ; une ConfigMap modifiée ne redémarre pas les pods.

Solutions :
- Générateur Kustomize (`configMapGenerator`) : nom suffixé par une empreinte du contenu, donc Deployment modifié à chaque changement (M09).
- Annotation d'empreinte dans le modèle de pod (ex. `checksum/config` dans un chart Helm, M09).
- Ponctuellement : `kubectl rollout restart` (hors Git, à éviter en GitOps).

## QCM — Réponses
1. **B** — `rollback cannot be initiated when auto-sync is enabled`.
2. **C** — Le revert est un commit : Git reste la source de vérité.
3. **B** — Le cluster exécute une ancienne révision, Git la version fautive : `OutOfSync`.
4. **C** — `revisionHistoryLimit` vaut 10 par défaut.
5. **A** — `argocd app diff --revision` compare le cluster à une révision Git donnée.
6. **C** — Sans `server.rbac.rollback.enforce.enable`, le rollback est contrôlé par `sync`.
7. **B** — L'automatisme resynchronise immédiatement sur la version encore présente dans Git.
