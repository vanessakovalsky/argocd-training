# M03 - Configurations testees (2026-11-08, ArgoCD v3.6.1, kind v1.36.4)

Module 03 redige (fr/module-03-configuration-acces-*). Notes de tests conservees pour la maintenance.

- argocd-cm n'est PAS vide en 3.x (resource.exclusions, ignoreResourceUpdates par defaut)
  -> modifier par `kubectl patch cm argocd-cm --type merge`, jamais apply du fichier complet.
- Banniere `ui.bannercontent` : renvoyee par /api/v1/settings uniquement aux utilisateurs connectes.
- argocd-rbac-cm : `kubectl apply` -> warning last-applied (installe en server-side) ; preferer `--server-side`.
- Resultats can-i : dev-alice sync flotte/* yes, default/* no, delete no ; audit-claire get yes, sync no ;
  ops-bob (role:admin) tout yes. `argocd admin settings rbac validate --policy-file` -> Policy is valid.
- ci-gitlab (apiKey) : `argocd account generate-token --account ci-gitlab --expires-in 168h --id formation` OK ;
  login par mot de passe refuse.
- AppProject flotte : destination namespace hors flotte-* -> InvalidSpecError ; depot non autorise -> "not permitted" ;
  CreateNamespace OK (Namespace en clusterResourceWhitelist).
- Builtin policy 3.6 : action `rollback` distincte de `sync` (a utiliser au M06).
- admin.enabled "false" -> "Account admin is disabled" (teste puis reactive).
- Dex GitLab (defi SSO) : callback `https://<ARGOCD>/api/dex/callback`, ne pas fixer redirectURI ; teste jusqu'a la redirection
  gitlab.com/oauth/authorize (redirect_uri et scope read_user openid conformes) ; login reel non teste (app OAuth requise).
- Depot de test = argocd-example-apps (public) ; en lab : https://gitlab.com/<GITLAB_USER>/flotte-config.git
  + deploy token (username/password dans le Secret) [A VERIFIER, non teste].
