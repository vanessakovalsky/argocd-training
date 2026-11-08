# Module 04 — Exercices

Modèles fournis : `labs/flotte-config/` (contenu de référence du dépôt `flotte-config`).

## Lab 04.1 ⭐ — Manifestes de `flotte-web` dans Git (guidé)
**Durée** : 25 min · **Objectif** : disposer de manifestes Kubernetes valides dans le dépôt `flotte-config`
**Contexte** : *Hexa Mobilité* remplace les `kubectl apply` depuis les postes par un dépôt de configuration unique.
**Prérequis** : clone local de `flotte-config` (Exercice 00.2), état final du M03

Variables : `<FLOTTE_CONFIG>` = chemin du clone local de `flotte-config` ; `<FORMATION>` = chemin du dépôt de la formation.

### Étapes
1. Créer l'arborescence et copier les manifestes de référence.
   ```bash
   cd <FLOTTE_CONFIG>
   mkdir -p apps/flotte-web argocd
   cp <FORMATION>/labs/flotte-config/apps/flotte-web/*.yaml apps/flotte-web/
   ls apps/flotte-web
   ```
   Résultat attendu :
   ```
   configmap.yaml  deployment.yaml  service.yaml
   ```
2. Lire `deployment.yaml` et repérer : image et tag, nombre de réplicas, sondes, référence à la ConfigMap.
3. Valider les manifestes auprès de l'API Kubernetes sans rien créer.
   ```bash
   kubectl apply --dry-run=server -n default -f apps/flotte-web/
   ```
   Résultat attendu :
   ```
   configmap/flotte-web-config created (server dry run)
   deployment.apps/flotte-web created (server dry run)
   service/flotte-web created (server dry run)
   ```
4. Committer et pousser.
   ```bash
   git add apps/
   git commit -m "feat: manifestes flotte-web 6.15.0"
   git push
   ```
   Résultat attendu (fin) : `main -> main`.

### Critères de réussite
- [ ] Les 3 fichiers sont visibles dans GitLab sous `apps/flotte-web/`
- [ ] `--dry-run=server` sans erreur

---

## Lab 04.2 ⭐ — Application déclarative et premier déploiement (guidé)
**Durée** : 20 min · **Objectif** : créer `flotte-web-dev` depuis un fichier versionné, la déployer et vérifier l'application
**Contexte** : l'équipe ops crée l'Application, l'équipe dev (`dev-alice`) la déploie.
**Prérequis** : Lab 04.1

### Étapes
1. Copier le modèle d'Application et renseigner l'URL du dépôt.
   ```bash
   cd <FLOTTE_CONFIG>
   sed "s|<GITLAB_USER>|$GITLAB_USER|" \
     <FORMATION>/labs/flotte-config/argocd/flotte-web-dev.yaml > argocd/flotte-web-dev.yaml
   grep repoURL argocd/flotte-web-dev.yaml
   ```
   Résultat attendu : `repoURL: https://gitlab.com/<GITLAB_USER>/flotte-config.git` avec l'identifiant réel.
2. Committer le fichier, puis créer l'Application (contexte administrateur).
   ```bash
   git add argocd/ && git commit -m "feat: application flotte-web-dev" && git push
   argocd context localhost:8443
   kubectl apply -f argocd/flotte-web-dev.yaml
   ```
   Résultat attendu :
   ```
   application.argoproj.io/flotte-web-dev created
   ```
   Un avertissement `prefer a domain-qualified finalizer name` (sur `metadata.finalizers`) peut s'afficher : sans conséquence.
3. Observer l'état initial, puis l'écart avec le cluster.
   ```bash
   argocd app get flotte-web-dev
   argocd app diff flotte-web-dev
   ```
   Résultat attendu : `Sync Status: OutOfSync`, `Health Status: Missing`, 3 ressources `OutOfSync` ; le diff affiche les 3 ressources complètes, avec l'annotation `argocd.argoproj.io/tracking-id`.
4. Synchroniser en tant que `dev-alice` (contexte `alice` créé au M03).
   ```bash
   argocd context alice
   argocd app sync flotte-web-dev
   argocd app wait flotte-web-dev --health
   ```
   Résultat attendu (fin) :
   ```
   Sync Status:        Synced to main (<COMMIT>)
   Health Status:      Healthy
   ```
5. Vérifier l'application déployée.
   ```bash
   kubectl get deploy,svc -n flotte-dev
   kubectl port-forward -n flotte-dev svc/flotte-web 9898:80
   ```
   Dans un second terminal :
   ```bash
   curl -s localhost:9898 | grep -E '"(version|message)"'
   ```
   Résultat attendu :
   ```
     "version": "6.15.0",
     "message": "Hexa Mobilite - suivi de flotte",
   ```
6. Dans l'UI, ouvrir `flotte-web-dev` : arbre des ressources, onglet *Summary* (révision, images), *App diff* vide.
7. Revenir au contexte administrateur : `argocd context localhost:8443`.

### Critères de réussite
- [ ] `flotte-web-dev` : `Synced` / `Healthy`, projet `flotte`
- [ ] `http://localhost:9898` affiche le message Hexa Mobilité et la version `6.15.0`
- [ ] Fichier `argocd/flotte-web-dev.yaml` présent dans GitLab

---

## Exercice 04.3 ⭐⭐ — Aperçu d'un chart Helm (semi-autonome)
**Durée** : 20 min · **Objectif** : déployer une application packagée depuis un dépôt de charts, sans copie du chart
**Contexte** : l'éditeur de `podinfo` publie un chart Helm ; l'équipe veut évaluer la version `6.16.0` dans un namespace d'aperçu.

**Énoncé** :
- (Contexte administrateur) Autoriser le dépôt de charts `https://stefanprodan.github.io/podinfo` dans le projet `flotte`.
- Écrire `argocd/flotte-web-helm.yaml` : Application `flotte-web-helm`, projet `flotte`, chart `podinfo` version `6.16.0`, nom de release `flotte-web`, 1 réplica, message d'UI `Hexa Mobilite - apercu Helm`, destination `flotte-preview` (création du namespace autorisée).
- Créer l'Application, vérifier le rendu AVANT synchronisation, puis synchroniser.
- Constater que `helm list -A` ne montre aucune release.
- Supprimer l'Application et vérifier que le namespace `flotte-preview` ne contient plus de Deployment.

**Indices** :
- `argocd proj add-source`
- Champs `source.chart`, `source.helm.releaseName`, `source.helm.valuesObject`
- `argocd app manifests <APP> --source git`

**Critères de réussite** :
- [ ] Rendu affichant `image: ghcr.io/stefanprodan/podinfo:6.16.0`
- [ ] `flotte-web-helm` : `Synced` / `Healthy`, Deployment `flotte-web-podinfo` à 1 réplica
- [ ] Application supprimée avec ses ressources

---

## Défi 04.4 ⭐⭐⭐ — Kustomize distant et révision figée (autonome)
**Durée** : 15 min · **Objectif** : déployer une source Kustomize et figer la révision déployée
**Contexte** : le dépôt public de `podinfo` fournit un dossier `kustomize/` ; l'équipe veut comparer son contenu à ses propres manifestes.

**Énoncé** :
- Déployer le dossier `kustomize` du dépôt `https://github.com/stefanprodan/podinfo.git`, au tag `6.17.0`, dans le namespace `flotte-kust`, via une Application déclarative du projet `flotte`.
- Lister les ressources créées et identifier celle qui n'existe pas dans `flotte-web`.
- Expliquer ce qui changerait si `targetRevision` valait `master`.
- Supprimer l'Application.

**Critères de réussite** :
- [ ] Application `Synced` / `Healthy`, révision `6.17.0` affichée
- [ ] Ressource supplémentaire identifiée et son rôle expliqué
- [ ] Différence tag / branche expliquée

---

## Bonus 🚀
Ajouter dans `flotte-config` un sous-dossier `apps/flotte-web/extra/` contenant une ConfigMap `flotte-extra`, pousser, puis rafraîchir `flotte-web-dev` : la ConfigMap est-elle prise en compte ? Ajouter ensuite `source.directory.recurse: true` à l'Application et observer le changement de statut. Revenir enfin à l'état initial (sous-dossier supprimé, `directory` retiré).
