# Module 03 — Exercices

Fichiers de travail fournis dans `scripts/m03/labs/` : `argocd-cm-accounts.yaml`, `argocd-rbac-cm.yaml`, `appproject-flotte.yaml`, `repo-flotte-config.yaml`.

## Lab 03.1 ⭐ — Personnaliser les paramètres (guidé)
**Durée** : 15 min · **Objectif** : modifier `argocd-cm` sans perdre la configuration par défaut
**Contexte** : *Hexa Mobilité* veut distinguer visuellement le cluster de formation et activer les badges de statut pour ses README.
**Prérequis** : état final du M02 (`https://localhost:8443`, CLI connectée en `admin`)

### Étapes
1. Observer le contenu par défaut de `argocd-cm`.
   ```bash
   kubectl get cm argocd-cm -n argocd -o jsonpath='{.data}' | tr ',' '\n' | cut -c1-70 | head -5
   ```
   Résultat attendu : clés `resource.customizations.ignoreResourceUpdates.*` et `resource.exclusions` présentes.
2. Ajouter l'URL publique, la bannière et les badges par un patch.
   ```bash
   kubectl patch cm argocd-cm -n argocd --type merge -p '{"data":{
     "url":"https://localhost:8443",
     "ui.bannercontent":"Cluster de formation - Hexa Mobilite",
     "statusbadge.enabled":"true"}}'
   ```
   Résultat attendu :
   ```
   configmap/argocd-cm patched
   ```
3. Vérifier que les valeurs par défaut sont conservées et que les nouvelles clés sont présentes.
   ```bash
   kubectl get cm argocd-cm -n argocd -o jsonpath='{.data.ui\.bannercontent}{"\n"}{.data.url}{"\n"}'
   kubectl get cm argocd-cm -n argocd -o yaml | grep -c 'resource.exclusions'
   ```
   Résultat attendu :
   ```
   Cluster de formation - Hexa Mobilite
   https://localhost:8443
   1
   ```
4. Recharger l'UI (`https://localhost:8443`) : la bannière apparaît en haut de chaque page (une fois connecté).

### Critères de réussite
- [ ] Bannière visible dans l'UI
- [ ] `resource.exclusions` toujours présent dans `argocd-cm`

---

## Lab 03.2 ⭐ — Comptes et rôles RBAC (guidé)
**Durée** : 30 min · **Objectif** : créer les comptes des trois équipes et leur attribuer des droits minimaux
**Contexte** : `dev-alice` (développement) déploie dans le projet `flotte`, `ops-bob` (exploitation) administre, `audit-claire` (audit) consulte ; `ci-gitlab` servira au pipeline (M10).
**Prérequis** : Lab 03.1

Variables : `<ADMIN_PASSWORD>` = mot de passe `admin` défini au M02.

### Étapes
1. Déclarer les comptes.
   ```bash
   cd scripts/m03/labs
   cat argocd-cm-accounts.yaml
   kubectl patch cm argocd-cm -n argocd --type merge --patch-file argocd-cm-accounts.yaml
   argocd account list
   ```
   Résultat attendu :
   ```
   NAME          ENABLED  CAPABILITIES
   admin         true     login
   audit-claire  true     login
   ci-gitlab     true     apiKey
   dev-alice     true     login
   ops-bob       true     login
   ```
2. Définir les mots de passe (convention de formation : `Mdp-<compte>-2026`).
   ```bash
   for u in dev-alice ops-bob audit-claire; do
     argocd account update-password --account "$u" \
       --current-password '<ADMIN_PASSWORD>' --new-password "Mdp-$u-2026"
   done
   ```
   Résultat attendu : 3 lignes `Password updated`.
3. Lire la politique fournie, puis la valider AVANT de l'appliquer.
   ```bash
   cat argocd-rbac-cm.yaml
   argocd admin settings rbac validate --policy-file argocd-rbac-cm.yaml
   ```
   Résultat attendu (dernière ligne) :
   ```
   Policy is valid.
   ```
4. Appliquer la politique.
   ```bash
   kubectl apply --server-side --force-conflicts -f argocd-rbac-cm.yaml
   ```
   Résultat attendu :
   ```
   configmap/argocd-rbac-cm serverside-applied
   ```
5. Se connecter en `dev-alice` dans un contexte CLI séparé et tester ses droits.
   ```bash
   argocd login localhost:8443 --username dev-alice --password 'Mdp-dev-alice-2026' \
     --insecure --name alice
   argocd account can-i sync applications 'flotte/flotte-web'
   argocd account can-i sync applications 'default/guestbook'
   argocd account can-i delete applications 'flotte/flotte-web'
   ```
   Résultat attendu :
   ```
   'dev-alice:login' logged in successfully
   Context 'alice' updated
   yes
   no
   no
   ```
6. Revenir au contexte administrateur.
   ```bash
   argocd context localhost:8443
   ```

### Critères de réussite
- [ ] 5 comptes listés, `ci-gitlab` avec la seule capacité `apiKey`
- [ ] `dev-alice` : `sync` autorisé sur `flotte/*`, refusé ailleurs, `delete` refusé
- [ ] Connexion UI en `dev-alice` : aucune application d'un autre projet visible

---

## Exercice 03.3 ⭐⭐ — Audit et jeton CI (semi-autonome)
**Durée** : 15 min · **Objectif** : vérifier le moindre privilège des comptes `audit-claire` et `ci-gitlab`
**Contexte** : l'équipe sécurité exige la preuve que l'audit ne peut rien modifier et que le compte CI ne peut pas se connecter à l'UI.

**Énoncé** :
- Vérifier, connecté en `audit-claire`, qu'il est possible de lire toutes les applications et leurs journaux, mais ni de synchroniser ni de créer un projet.
- Générer un jeton d'une validité de 7 jours, identifiant `formation`, pour `ci-gitlab` ; l'enregistrer dans le gestionnaire de mots de passe (utilisé au M10).
- Prouver que `ci-gitlab` ne peut pas se connecter par mot de passe, et que son jeton permet de lister les applications.
- Révoquer puis régénérer le jeton (simulation de fuite).

**Indices** :
- `argocd account can-i <action> <ressource> <objet>`
- `argocd account generate-token`, `argocd account get`, `argocd account delete-token`
- Option globale `--auth-token` de la CLI

**Critères de réussite** :
- [ ] Tableau de 4 tests `can-i` pour `audit-claire` (2 `yes`, 2 `no`)
- [ ] Jeton `formation` visible dans `argocd account get --account ci-gitlab`, avec date d'expiration
- [ ] `argocd app list --auth-token <JETON>` répond ; connexion par mot de passe refusée

---

## Lab 03.4 ⭐ — Projet `flotte` et dépôt privé (guidé)
**Durée** : 25 min · **Objectif** : isoler les applications de *Hexa Mobilité* et connecter le dépôt `flotte-config`
**Contexte** : le dépôt privé `flotte-config` (créé au M00) doit être lu par ArgoCD avec un accès en lecture seule.
**Prérequis** : Exercice 00.2 (projet GitLab `flotte-config`), Lab 03.2

Variables : `<GITLAB_USER>` = identifiant GitLab ; `<GITLAB_DEPLOY_USER>` et `<GITLAB_DEPLOY_TOKEN>` = nom et valeur du jeton de déploiement créé à l'étape 1.

### Étapes
1. Dans GitLab, projet `flotte-config` → *Settings* → *Repository* → *Deploy tokens* → *Add token* : nom `argocd`, portée `read_repository`, expiration à J+7. Noter le nom d'utilisateur affiché (`gitlab+deploy-token-<N>`) et le jeton (affiché une seule fois).
2. Préparer les fichiers en remplaçant les variables.
   ```bash
   cd scripts/m03/labs
   export GITLAB_USER=<GITLAB_USER>
   export GITLAB_DEPLOY_USER=<GITLAB_DEPLOY_USER>
   export GITLAB_DEPLOY_TOKEN=<GITLAB_DEPLOY_TOKEN>
   sed -e "s|\${GITLAB_USER}|$GITLAB_USER|g" appproject-flotte.yaml > /tmp/appproject.yaml
   sed -e "s|\${GITLAB_USER}|$GITLAB_USER|g" \
       -e "s|\${GITLAB_DEPLOY_USER}|$GITLAB_DEPLOY_USER|g" \
       -e "s|\${GITLAB_DEPLOY_TOKEN}|$GITLAB_DEPLOY_TOKEN|g" repo-flotte-config.yaml > /tmp/repo.yaml
   ```
3. Créer le projet, puis le dépôt.
   ```bash
   kubectl apply -f /tmp/appproject.yaml -f /tmp/repo.yaml
   rm /tmp/repo.yaml
   ```
   Résultat attendu :
   ```
   appproject.argoproj.io/flotte created
   secret/repo-flotte-config created
   ```
4. Vérifier le projet et la connexion au dépôt.
   ```bash
   argocd proj get flotte
   argocd repo list
   ```
   Résultat attendu (extraits) :
   ```
   Name:                        flotte
   Destinations:                https://kubernetes.default.svc,flotte-*
   Repositories:                https://gitlab.com/<GITLAB_USER>/flotte-config.git
   Allowed Cluster Resources:   /Namespace
   ```
   puis une ligne de dépôt avec `CREDS` = `true`, `STATUS` = `Successful`, `PROJECT` = `flotte`.
5. Dans l'UI : *Settings* → *Projects* → `flotte`, puis *Settings* → *Repositories* : retrouver les mêmes informations.

### Critères de réussite
- [ ] `argocd repo list` : `Successful` pour `flotte-config`
- [ ] `argocd proj get flotte` : un seul dépôt, destinations `flotte-*`, ressource cluster `Namespace` uniquement
- [ ] Fichier contenant le jeton supprimé (`/tmp/repo.yaml`)

---

## Exercice 03.5 ⭐⭐ — Éprouver les frontières du projet (semi-autonome)
**Durée** : 15 min · **Objectif** : constater la double barrière RBAC + AppProject
**Contexte** : avant d'ouvrir l'accès à l'équipe dev, l'équipe ops vérifie qu'aucun déploiement hors périmètre n'est possible.

**Énoncé** : connecté en `dev-alice` (contexte `alice`), tenter de créer quatre applications et relever le message obtenu :
- `test-ok` : dépôt `flotte-config`, chemin `.`, namespace `flotte-dev`, option de synchronisation `CreateNamespace=true` ;
- `test-ns` : même dépôt, namespace `default` ;
- `test-repo` : dépôt `https://github.com/argoproj/argocd-example-apps.git`, chemin `guestbook`, namespace `flotte-dev` ;
- `test-projet` : dépôt `flotte-config`, projet `default`.
Puis tenter de supprimer `test-ok`. Terminer en supprimant `test-ok` depuis le contexte administrateur.

**Indices** : `argocd app create <NOM> --project <PROJET> --repo <URL> --path <CHEMIN> --dest-server <SERVEUR> --dest-namespace <NS>` ; message d'erreur en fin de ligne `fatal`.

**Critères de réussite** :
- [ ] Tableau des 5 tentatives : résultat et barrière responsable (RBAC ou projet)
- [ ] `test-ok` créée puis supprimée par un administrateur

---

## Défi 03.6 ⭐⭐⭐ — Connexion SSO GitLab avec Dex (autonome)
**Durée** : 20 min · **Objectif** : remplacer les comptes locaux par l'identité GitLab
**Contexte** : *Hexa Mobilité* veut gérer les accès par les groupes GitLab de ses équipes plutôt que par des comptes locaux.

**Énoncé** :
- Créer une application OAuth dans GitLab (*Edit profile* → *Applications*) avec l'URL de rappel `https://localhost:8443/api/dex/callback`.
- Configurer le connecteur Dex `gitlab` dans `argocd-cm` (`dex.config`), secret client stocké dans `argocd-secret`.
- Se connecter à l'UI avec le bouton *Log in via GitLab* et attribuer `role:readonly` à son propre utilisateur ou groupe GitLab dans `argocd-rbac-cm`.

**Critères de réussite** :
- [ ] Bouton de connexion GitLab visible, connexion réussie
- [ ] `argocd account get-user-info` (après `argocd login --sso`) affiche l'identité GitLab
- [ ] Droits limités à la lecture pour l'utilisateur SSO

---

## Bonus 🚀
Désactiver le compte `admin` (`admin.enabled: "false"`) après avoir vérifié que `ops-bob` dispose de `role:admin`. Prouver que `admin` est refusé, que `ops-bob` peut tout faire, puis réactiver `admin` pour la suite de la formation (les scripts de rattrapage l'utilisent).
