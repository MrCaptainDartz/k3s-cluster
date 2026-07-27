# TODO: Évolution du Cluster K3s vers l'État de l'Art

Ce document liste les tâches à accomplir pour améliorer l'infrastructure GitOps, suite à l'analyse de la baseline.

## 1. Notifications GitOps (ArgoCD vers Telegram)
- [ ] Récupérer le token du bot Telegram utilisé actuellement pour Alertmanager, ou en créer un dédié à ArgoCD.
- [ ] Créer le `Secret` Kubernetes contenant le token Telegram dans le namespace `argocd`.
- [ ] Activer `argocd-notifications` dans la configuration Ansible (`09-argocd.yml.j2`) ou via GitOps si géré par Helm.
- [ ] Configurer le `ConfigMap` des notifications (triggers et templates) pour envoyer un message sur `SyncFailed` ou `Degraded`.
- [ ] Annoter les applications ArgoCD pour s'abonner aux notifications Telegram.

## 2. Sécurité & Conformité de la Posture (Kyverno & Trivy Operator)
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/kyverno/`.
- [ ] Configurer les politiques Kyverno pour appliquer les Pod Security Standards (PSS Restricted).
- [ ] Bloquer les images sans tag fixe ou utilisant le tag `:latest`, et imposer le TLS sur les Ingresses.
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/trivy/`.
- [ ] Déployer Trivy Operator pour analyser en continu les vulnérabilités (CVE) des workloads et exporter les métriques dans Grafana.

## 3. Gestion des Identités et SSO (Authelia ou Authentik)
- [ ] Déterminer la solution à utiliser (Authelia pour sa légèreté ou Authentik pour ses fonctionnalités complètes).
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/sso/`.
- [ ] Préparer les manifestes Helm/Kustomize pour déployer l'Identity Provider (IdP).
- [ ] Configurer le middleware `Traefik ForwardAuth` pour protéger les services internes (sans auth native).
- [ ] (Optionnel) Configurer l'intégration OIDC pour les applications compatibles (Proxmox, Grafana, ArgoCD).

## 4. Automatisation des Dépendances (Renovate)
- [ ] Installer l'application GitHub/GitLab Renovate sur le dépôt ou préparer le déploiement d'un runner local.
- [ ] Créer le fichier `renovate.json` à la racine du dépôt.
- [ ] Configurer Renovate pour scanner les fichiers Ansible, valeurs Helm, et Kustomizations.
- [ ] (Optionnel) Configurer l'auto-merge pour les patchs et mises à jour mineures afin de réduire la charge mentale.

## 5. Portail Homelab Unifié (Homepage) & K8s Gateway API
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/homepage/`.
- [ ] Configurer Homepage pour la découverte automatique des Ingress/Services Kubernetes et l'affichage des métriques du cluster.
- [ ] Protéger l'accès au tableau de bord Homepage via le middleware SSO.
- [ ] Préparer la transition des Ingresses Traefik v3 vers la Kubernetes Gateway API (`gateway.networking.k8s.io`).