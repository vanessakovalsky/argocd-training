# Module 10 — Exercices

Fichiers fournis : `labs/flotte-app/` (`Dockerfile`, `.gitlab-ci.yml`, `ci/update-config.sh`, `Jenkinsfile`), `labs/m10/gitlab-push.json`. Contexte CLI administrateur : `argocd context localhost:8443`.

## Lab 10.1 ⭐ — Pipeline GitLab CI de `flotte-app` (guidé)
**Durée** : 25 min · **Objectif** : construire l'image `flotte-web` à chaque commit et mettre à jour `flotte-config`
**Contexte** : jusqu'ici, les tags d'image étaient modifiés à la main ; *Hexa Mobilité* confie ce geste à la CI.
**Prérequis** : état final du M09 ; projet GitLab `flotte-app` (Exercice 00.2) ; jeton `formation-argocd` (`write_repository`, M00)

Variables : `<GITLAB_USER>` = identifiant GitLab ; `<TOKEN>` = jeton `formation-argocd`.

### Étapes
1. Rendre le registre de `flotte-app` lisible par le cluster : *Settings* → *General* → *Visibility* → projet **Public** (le code ne contient qu'un `Dockerfile`). En entreprise : registre privé et `imagePullSecret` (M11).
2. Déclarer les variables CI/CD de `flotte-app` : *Settings* → *CI/CD* → *Variables*.

   | Clé | Valeur | Options |
   |---|---|---|
   | `FLOTTE_CONFIG_URL` | `https://gitlab.com/<GITLAB_USER>/flotte-config.git` | — |
   | `FLOTTE_CONFIG_TOKEN` | `<TOKEN>` | *Masked*, *Protected* |

3. Pousser le code fourni dans `flotte-app`.
   ```bash
   git clone "https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-app.git"
   cd flotte-app
   cp -r <FORMATION>/labs/flotte-app/{Dockerfile,.gitlab-ci.yml,ci,Jenkinsfile} .
   git add -A && git commit -m "feat: pipeline de construction" && git push
   ```
4. Suivre le pipeline : *Build* → *Pipelines* (2 jobs : `build-image`, `update-config`).
   Résultat attendu (journal de `update-config`, fin) :
   ```
   flotte-config updated: registry.gitlab.com/<GITLAB_USER>/flotte-app:<SHA_COURT>
   Job succeeded
   ```
5. Vérifier l'image publiée : *Deploy* → *Container registry* → `flotte-app`, tag `<SHA_COURT>`.

### Critères de réussite
- [ ] Pipeline vert, 2 jobs réussis
- [ ] Image `flotte-app:<SHA_COURT>` dans le registre
- [ ] Commit `ci: flotte-web dev -> registry.gitlab.com/<GITLAB_USER>/flotte-app:<SHA_COURT>` dans `flotte-config`

---

## Lab 10.2 ⭐ — De la CI au pod (guidé)
**Durée** : 15 min · **Objectif** : vérifier la chaîne complète et la traçabilité commit → image → déploiement
**Contexte** : l'équipe dev veut savoir quel commit de code tourne en `dev`.
**Prérequis** : Lab 10.1

### Étapes
1. Rafraîchir l'application (le cluster local ne reçoit pas les webhooks de GitLab.com) et suivre le canari.
   ```bash
   argocd app get flotte-web-dev --refresh > /dev/null
   kubectl argo rollouts get rollout flotte-web -n flotte-dev | grep -E 'Status|Images' -A1
   ```
   Résultat attendu : image `registry.gitlab.com/<GITLAB_USER>/flotte-app:<SHA_COURT> (canary)`, analyse puis pause.
2. Promouvoir, puis relier l'image au commit de code.
   ```bash
   kubectl argo rollouts promote flotte-web -n flotte-dev --full
   argocd app wait flotte-web-dev --health
   argocd app get flotte-web-dev -o yaml | grep -A2 'images:'
   git -C <FLOTTE_APP> log --oneline -1
   ```
   Résultat attendu : image `flotte-app:<SHA_COURT>` ; le même `<SHA_COURT>` en tête de `git log` de `flotte-app`.
3. Modifier le `Dockerfile` (par exemple un label), pousser, et mesurer le temps entre le push et le pod en `dev`.

### Critères de réussite
- [ ] Chaîne complète observée : commit → pipeline → commit de configuration → canari → promotion
- [ ] SHA du commit de code retrouvé dans l'image déployée
- [ ] Durée de bout en bout relevée, avec la part due au délai de détection

---

## Exercice 10.3 ⭐⭐ — Webhook avec secret (semi-autonome)
**Durée** : 15 min · **Objectif** : remplacer l'attente de la réconciliation par une notification de GitLab
**Contexte** : en production, ArgoCD est joignable par GitLab ; l'équipe veut un déploiement immédiat après chaque commit de configuration.

**Énoncé** :
- Configurer le secret du webhook GitLab dans ArgoCD (`formation-webhook-2026`).
- Le cluster `kind` n'étant pas joignable depuis GitLab.com, simuler l'appel de GitLab : adapter `labs/m10/gitlab-push.json` (URL de `flotte-config`, SHA du dernier commit) et l'envoyer à `https://localhost:8443/api/webhook` avec les en-têtes de GitLab.
- Mesurer le délai entre l'appel et le changement d'état de `flotte-web-dev`, puis comparer avec un push sans webhook.
- Envoyer le même appel avec un mauvais jeton et observer la réponse.
- Décrire la configuration à réaliser côté GitLab (`flotte-config` → *Settings* → *Webhooks*) pour un ArgoCD joignable.

**Indices** : clé `webhook.gitlab.secret` de `argocd-secret` ; en-têtes `X-Gitlab-Event: Push Hook` et `X-Gitlab-Token`.

**Critères de réussite** :
- [ ] Rafraîchissement en quelques secondes après l'appel
- [ ] Appel avec un mauvais jeton sans effet
- [ ] Configuration GitLab décrite (URL, jeton, événement *Push*, vérification SSL)

---

## Défi 10.4 ⭐⭐⭐ — La CI attend le résultat du déploiement (autonome)
**Durée** : 15 min (conception) · **Objectif** : faire échouer le pipeline si le déploiement en `dev` échoue
**Contexte** : les développeurs veulent voir dans GitLab si leur commit a réellement été déployé.

**Énoncé** :
- Écrire un job `verify-deploy` (étape après `update-config`) qui utilise la CLI `argocd` avec le jeton du compte `ci-gitlab` (M03) pour attendre que `flotte-web-dev` soit synchronisée sur le nouveau commit et `Healthy`.
- Tester la commande d'attente depuis le poste avec le jeton `ci-gitlab` (le runner de GitLab.com ne peut pas joindre le cluster `kind`).
- Lister les conditions réseau et de sécurité pour l'utiliser en entreprise (runner, exposition d'ArgoCD, droits du jeton).
- Expliquer pourquoi ce job doit tolérer la pause manuelle du canari.

**Critères de réussite** :
- [ ] Job `verify-deploy` écrit (image, variables, commandes, délai maximal)
- [ ] Commande d'attente testée avec `--auth-token`
- [ ] Conditions d'usage en entreprise et cas du canari en pause expliqués

---

## Bonus 🚀
Lire le `Jenkinsfile` fourni et le comparer, étape par étape, au `.gitlab-ci.yml` : déclenchement, gestion des identifiants, image d'exécution, condition sur la branche. Puis rechercher dans la documentation d'Argo CD Image Updater comment obtenir le même résultat sans job `update-config`, et en citer deux limites.
