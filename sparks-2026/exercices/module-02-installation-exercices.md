# Module 02 — Exercices

## Lab 02.1 ⭐ — Créer le cluster et installer ArgoCD (guidé)
**Durée** : 25 min · **Objectif** : disposer d'ArgoCD v3.6.1 opérationnel sur un cluster local
**Contexte** : *Hexa Mobilité* installe sa plateforme GitOps sur un cluster de test avant la production.
**Prérequis** : Lab 00.1 réussi (`preflight.sh` sans KO), dépôt de la formation cloné

### Étapes
1. Créer le cluster `kind` à partir de la configuration fournie.
   ```bash
   kind create cluster --config scripts/setup/kind-config.yaml
   ```
   Résultat attendu (fin) :
   ```
   You can now use your cluster with:

   kubectl cluster-info --context kind-argocd-formation
   ```
2. Vérifier le nœud et le contexte courant.
   ```bash
   kubectl config current-context
   kubectl get nodes
   ```
   Résultat attendu :
   ```
   kind-argocd-formation
   NAME                             STATUS   ROLES           AGE   VERSION
   argocd-formation-control-plane   Ready    control-plane   40s   v1.36.4
   ```
3. (Facultatif, gain de temps) Charger dans le nœud les images préchargées au M00.
   ```bash
   ./scripts/setup/pull-images.sh
   ```
   Résultat attendu : lignes `loaded quay.io/argoproj/argocd:v3.6.1` (et autres images), puis `done`.
4. Créer le namespace et installer ArgoCD v3.6.1.
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd --server-side --force-conflicts \
     -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml
   ```
   Résultat attendu : une ligne `serverside-applied` par objet, dont :
   ```
   customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io serverside-applied
   deployment.apps/argocd-server serverside-applied
   statefulset.apps/argocd-application-controller serverside-applied
   ```
5. Attendre la disponibilité de tous les composants.
   ```bash
   kubectl wait --for=condition=Available deployment --all -n argocd --timeout=600s
   kubectl rollout status statefulset/argocd-application-controller -n argocd
   kubectl get pods -n argocd
   ```
   Résultat attendu : 6 lignes `condition met`, puis 7 pods `1/1 Running`.
6. Relever la version installée.
   ```bash
   kubectl get deploy argocd-server -n argocd \
     -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
   ```
   Résultat attendu :
   ```
   quay.io/argoproj/argocd:v3.6.1
   ```

### Critères de réussite
- [ ] `kubectl get pods -n argocd` : 7 pods `Running`, colonne `READY` à `1/1`
- [ ] Image `quay.io/argoproj/argocd:v3.6.1`
- [ ] `kubectl get crd | grep argoproj` : 3 CRD (`applications`, `applicationsets`, `appprojects`)

---

## Lab 02.2 ⭐ — Accéder à l'UI et à la CLI (guidé)
**Durée** : 20 min · **Objectif** : se connecter, sécuriser le compte `admin`, explorer le tableau de bord
**Contexte** : premier accès de l'équipe ops d'*Hexa Mobilité* à ArgoCD.
**Prérequis** : Lab 02.1 réussi

Variables : `<ADMIN_PASSWORD>` = nouveau mot de passe `admin` choisi (8 caractères minimum, à conserver pour toute la formation).

### Étapes
1. Ouvrir un tunnel vers le service `argocd-server` (terminal dédié, laissé ouvert).
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
   Résultat attendu :
   ```
   Forwarding from 127.0.0.1:8080 -> 8080
   Forwarding from [::1]:8080 -> 8080
   ```
2. Dans un second terminal, afficher le mot de passe initial.
   ```bash
   argocd admin initial-password -n argocd
   ```
   Résultat attendu : une chaîne de 16 caractères, suivie d'un avertissement recommandant de changer le mot de passe.
3. Se connecter avec la CLI (utilisateur `admin`, mot de passe de l'étape 2).
   ```bash
   argocd login localhost:8080 --username admin --insecure
   ```
   Résultat attendu :
   ```
   'admin:login' logged in successfully
   Context 'localhost:8080' updated
   ```
4. Changer le mot de passe, puis vérifier l'identité connectée.
   ```bash
   argocd account update-password
   argocd account get-user-info
   ```
   Résultat attendu :
   ```
   Password updated
   Context 'localhost:8080' updated
   Logged In: true
   Username: admin
   Issuer: argocd
   Groups:
   ```
5. Supprimer le secret initial devenu inutile.
   ```bash
   kubectl delete secret argocd-initial-admin-secret -n argocd
   ```
   Résultat attendu :
   ```
   secret "argocd-initial-admin-secret" deleted from argocd namespace
   ```
6. Ouvrir `https://localhost:8080` dans le navigateur, accepter le certificat auto-signé, se connecter avec `admin` / `<ADMIN_PASSWORD>`.
7. Explorer *Settings* → *Clusters* : relever le cluster déclaré par défaut. Contrôle en CLI :
   ```bash
   argocd cluster list
   ```
   Résultat attendu :
   ```
   SERVER                          NAME        VERSION  STATUS   MESSAGE
   https://kubernetes.default.svc  in-cluster  1.36.4   Unknown  Cluster has no applications and is not being monitored.
   ```
8. Déployer l'application d'exemple `guestbook`, puis la synchroniser.
   ```bash
   argocd app create guestbook \
     --repo https://github.com/argoproj/argocd-example-apps.git --path guestbook \
     --dest-server https://kubernetes.default.svc --dest-namespace default
   argocd app sync guestbook
   argocd app get guestbook
   ```
   Résultat attendu (fin de `argocd app get`) :
   ```
   Sync Status:        Synced to  (8088f4c)
   Health Status:      Healthy

   GROUP  KIND        NAMESPACE  NAME          STATUS  HEALTH   HOOK  MESSAGE
          Service     default    guestbook-ui  Synced  Healthy        service/guestbook-ui created
   apps   Deployment  default    guestbook-ui  Synced  Healthy        deployment.apps/guestbook-ui created
   ```
   Le hash de commit (`8088f4c`) dépend de l'état du dépôt d'exemple au moment du lab.
9. Dans l'UI, ouvrir la tuile `guestbook` : parcourir l'arbre (Deployment → ReplicaSet → Pod), ouvrir le manifeste *Live* du Deployment, puis les journaux du pod.
10. Supprimer l'application et ses ressources.
    ```bash
    argocd app delete guestbook --yes
    kubectl get deploy,svc -n default
    ```
    Résultat attendu : seul `service/kubernetes` subsiste dans le namespace `default`.

### Critères de réussite
- [ ] Connexion UI et CLI avec `<ADMIN_PASSWORD>` (ancien mot de passe refusé)
- [ ] `kubectl get secret argocd-initial-admin-secret -n argocd` : `NotFound`
- [ ] `guestbook` observée `Synced` / `Healthy`, puis supprimée avec ses ressources

---

## Exercice 02.3 ⭐⭐ — Exposer l'UI sans port-forward (semi-autonome)
**Durée** : 15 min · **Objectif** : rendre l'UI accessible en permanence sur `https://localhost:8443`
**Contexte** : le tunnel `port-forward` s'interrompt à chaque fermeture de terminal ; l'équipe veut un accès stable au cluster de test.

**Énoncé** :
- Passer le service `argocd-server` en type `NodePort`, avec le port `https` (443) exposé sur le NodePort `30443`.
- Vérifier que `https://localhost:8443` répond sans `port-forward` (le fichier `scripts/setup/kind-config.yaml` relie déjà le port 8443 du poste au port 30443 du nœud).
- Se reconnecter avec la CLI sur ce nouveau point d'accès, puis arrêter le `port-forward` du Lab 02.2.

**Indices** :
- `kubectl patch svc` (patch de type `merge`) ou `kubectl edit svc`
- Les deux ports du service (80 et 443) pointent sur le même `targetPort: 8080` du pod
- Le point de terminaison `/healthz` répond `ok` sans authentification

**Critères de réussite** :
- [ ] `kubectl get svc argocd-server -n argocd` : `TYPE` = `NodePort`, port `443:30443/TCP`
- [ ] `curl -sk https://localhost:8443/healthz` affiche `ok`
- [ ] `argocd login localhost:8443 --username admin --insecure` réussit, `port-forward` arrêté

---

## Défi 02.4 ⭐⭐⭐ — Installation reproductible avec Kustomize (autonome)
**Durée** : 15 min · **Objectif** : décrire l'installation d'ArgoCD de façon déclarative, versionnée et personnalisée
**Contexte** : l'équipe ops d'*Hexa Mobilité* refuse les modifications manuelles (`kubectl patch`) : toute personnalisation d'ArgoCD doit être décrite dans des fichiers.

**Énoncé** :
- Créer un dossier `argocd-install/` contenant un `kustomization.yaml` qui :
  - référence le manifeste officiel `install.yaml` de la version v3.6.1 (URL distante) ;
  - place toutes les ressources dans le namespace `argocd` ;
  - applique un patch qui reproduit l'exposition NodePort 30443 de l'exercice 02.3.
- Vérifier le rendu sans l'appliquer, puis l'appliquer sur le cluster.
- Expliquer pourquoi cette approche facilite la montée de version vers v3.6.2.

**Critères de réussite** :
- [ ] `kubectl kustomize argocd-install/` produit un Service `argocd-server` de type `NodePort`
- [ ] Application réussie avec `kubectl apply -k argocd-install/ --server-side --force-conflicts`
- [ ] Montée de version expliquée (une seule ligne modifiée : l'URL de version)

---

## Bonus 🚀
Tester l'accès « core » de la CLI, qui contourne `argocd-server` et utilise directement le kubeconfig : `argocd login --core`, puis `argocd app list`. Identifier ce qui change pour l'authentification et le RBAC ArgoCD (indice : documentation *Argo CD Core*). Revenir ensuite au contexte `localhost:8443` (`argocd context localhost:8443`).
