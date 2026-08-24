 ──────
   Plan de Déploiement Définitif : K3s + ESO + OpenBao (Master Plan)
  ──────
  ## 1. Contexte & Architecture Globale
  OpenBao 2.6 est déployé sur la VM dédiée infra-services (10.20.4.253) avec le moteur KV v2 (secret/),
  la policy eso-k3s-policy (lecture sur secret/{data,metadata}/k3s/*) et l'AppRole ansible.
  Le cluster K3s est déployé from scratch :

  • Abandon total de SOPS : zéro fichier chiffré dans Git, zéro clé age, suppression du sops-operator.
  • External Secrets Operator (ESO) déployé par ArgoCD en sync-wave -10 (remplace sops-providers).
  • Authentification Kubernetes (auth/kubernetes) : ESO s'authentifie auprès d'OpenBao via le jeton JWT
  court de son ServiceAccount natif.
  • Moindre Privilège (Zéro Root Token) : le playbook ansible-k3s/playbook.yml s'authentifie auprès
  d'OpenBao via l'AppRole ansible (avec droits délégués sur auth/kubernetes) pour configurer la liaison
  K3s ↔ OpenBao.
  • Cycle de vie découplé & Secrets pérennes :
      • ansible-services héberge les secrets de manière persistante dans OpenBao KV.
      • Le cluster K3s est éphémère et s'auto-enregistre auprès d'OpenBao à la fin de son déploiement
      (ansible-k3s playbook.yml).
  ──────
  ## 2. Décisions Techniques & Ordonnancement
  ┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                    VM INFRA-SERVICES (10.20.4.253)
  │
    │  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
  │
    │  │                                           OpenBao                                           │
  │
    │  │  - secret/data/k3s/* (Secrets d'infra pré-peuplés au bootstrap ansible-services)            │
  │
    │  │  - auth/approle (Utilisé par ansible-k3s pour auto-enregistrement)                          │
  │
    │  │  - auth/kubernetes (Utilisé par ESO pour récupérer les secrets applicatifs)                │
  │
    │  └──────────────────────────────────────────────▲──────────────────────────────────────────────┘
  │

  └─────────────────────────────────────────────────┼─────────────────────────────────────────────────┘
                                                      │
                                 1. Auto-enregistrement│  2. Récupération des secrets
                                    via AppRole       │     via K8s Auth (JWT ESO)
                                    (playbook.yml)    │
  ┌─────────────────────────────────────────────────┴─────────────────────────────────────────────────┐
    │                                            CLUSTER K3S
  │
    │
  │
    │  [kube-system]                  [external-secrets]                  [Namespaces Applicatifs]
  │
    │  ServiceAccount:                ESO Pod (Controller) ─────────────► Secret natif K8s
  │
    │  `vault-reviewer`               (Wave -10 ArgoCD)                    (Cert-Manager, Monitoring,
  │
    │  (Valide les jetons)                                                 Ceph CSI, ExternalDNS)
  │
  └───────────────────────────────────────────────────────────────────────────────────────────────────┘
  ### Échelle des Sync-Waves ArgoCD (App-of-Apps / root-app) :

   Sync-Wave | Application                | Rôle
  -----------|----------------------------|------------------------------------------------------------
      -10    | external-secrets           | Opérateur de secrets (fournisseur de tous les credentials)
      -9     | external-snapshotter       | CRDs VolumeSnapshot
      -8     | ceph-csi, nfs-csi, smb-csi | Pilotes de stockage (consomment les secrets Ceph)
      -7     | cert-manager               | Certificats TLS (consomme le token Infomaniak)
      -6     | external-dns               | Enregistrements DNS (consomme le token Infomaniak)
      -5     | observability              | Monitoring (consomme Alertmanager config & Grafana admin)
      -4     | kured                      | Reboot daemon

  ### Paramètres de sécurité :

  1. Endpoint OpenBao : https://openbao.infra-services.local:443 (Fallback documenté : https://10.20.4.
  253:443).
  2. Audience JWT : https://kubernetes.default.svc.cluster.local (alignée sur K3s, OpenBao et ESO
  ClusterSecretStore).
  3. CA K3s : /var/lib/rancher/k3s/server/tls/server-ca.crt (servi par le VIP 10.20.4.10:6443).
  4. Point d'ancrage bootstrap unique : argocd-repo-creds (clé SSH Git) créée par ansible-k3s reste le
  seul secret hors-Git.
  ──────
  ## 3. Détail des Fichiers par Composant
  ──────
  ### Phase 1 — ansible-services : Policy AppRole & Pré-peuplement KV v2

  #### 1.1 Enrichissement de la policy ansible-policy

  Dans ansible-services/roles/openbao/tasks/main.yml, enrichir la policy ansible-policy :

    # Gestion des secrets KV v2 pour infra, k3s et apps
    path "secret/data/infra/*" { capabilities = ["create", "read", "update", "delete"] }
    path "secret/metadata/infra/*" { capabilities = ["read", "list"] }
    path "secret/data/k3s/*" { capabilities = ["create", "read", "update", "delete"] }
    path "secret/metadata/k3s/*" { capabilities = ["read", "list"] }
    path "secret/data/apps/*" { capabilities = ["create", "read", "update", "delete"] }
    path "secret/metadata/apps/*" { capabilities = ["read", "list"] }
    
    # Gestion déléguée du moteur d'auth Kubernetes pour K3s
    path "sys/auth/kubernetes" { capabilities = ["create", "read", "update", "delete", "sudo"] }
    path "sys/auth/kubernetes/*" { capabilities = ["create", "read", "update", "delete", "sudo"] }
    path "sys/auth" { capabilities = ["read"] }
    path "auth/kubernetes/*" { capabilities = ["create", "read", "update", "delete", "list"] }

  #### 1.2 Tâches de pré-peuplement des secrets dans le rôle openbao

  Ajouter dans ansible-services/roles/openbao/defaults/main.yml :

    openbao_provision_k3s_secrets: false # Désactivé par défaut si non configuré dans l'inventaire
    openbao_k3s_secrets: []


  Ajouter dans le rôle openbao la création idempotente des 6 secrets (chemins complets sous secret/data/<path>, préfixés par défaut par `k3s/`) :

  • k3s/ceph-csi-operator-system/csi-rbd-secret (userID, userKey)
  • k3s/ceph-csi-operator-system/csi-cephfs-secret (userID, userKey)
  • k3s/cert-manager/infomaniak-api-credentials (api-token)
  • k3s/external-dns/infomaniak-api-token-cluster-domain (api-token)
  • k3s/monitoring/alertmanager-telegram (bot-token, chat-id)
  • k3s/monitoring/grafana-admin-credentials (admin-user, admin-password)
  ──────
  ### Phase 2 — ansible-k3s : Nettoyage SOPS & Auto-enregistrement OpenBao

  #### 2.1 Nettoyage SOPS

  1. Supprimer 08-sops-operator.yml.j2.
  2. Nettoyer all.yml.example :
      • Retirer 08-sops-operator.yml.j2 de k3s_server_manifests_templates.
      • Supprimer la variable age_private_key.
  3. Nettoyer 05-network-policies.yml.j2 : supprimer les 2 NetworkPolicies secrets-system.
  4. Ajouter le namespace external-secrets (PSS enforce: restricted) dans 07-pod-security.yml.j2.

  #### 2.2 Variables OpenBao dans inventory/group_vars/all.yml

   Les identifiants AppRole sont copiés directement (valeurs réelles dans all.yml — gitignored —
  issues d'ansible-services/output/openbao-credentials.txt, placeholders dans all.yml.example). Le
  credentials.txt n'est pas référencé par lookup pour éviter une dépendance fichier inter-projets.

    openbao_url: "https://openbao.infra-services.local"
    openbao_approle_role_id: "<Role ID depuis ansible-services/output/openbao-credentials.txt>"
    openbao_approle_secret_id: "<Secret ID depuis ansible-services/output/openbao-credentials.txt>"
    openbao_ca_cert_path: "{{ playbook_dir }}/../ansible-services/output/openbao-ca.crt"

  #### 2.3 Tâches dans ansible-k3s/playbook.yml (rôle openbao_registration sur k3s_cluster[0])

        # 1. Déploiement du ServiceAccount vault-reviewer sur K3s
        - name: Deploy vault-reviewer ServiceAccount, Secret and RBAC on K3s
          ansible.builtin.shell: |
            /usr/local/bin/k3s kubectl apply -f - <<'EOF'
            apiVersion: v1
            kind: ServiceAccount
            metadata:
              name: vault-reviewer
              namespace: kube-system
            ---
            apiVersion: v1
            kind: Secret
            metadata:
              name: vault-reviewer-token
              namespace: kube-system
              annotations:
                kubernetes.io/service-account.name: vault-reviewer
            type: kubernetes.io/service-account-token
            ---
            apiVersion: rbac.authorization.k8s.io/v1
            kind: ClusterRoleBinding
            metadata:
              name: openbao-vault-reviewer
            roleRef:
              apiGroup: rbac.authorization.k8s.io
              kind: ClusterRole
              name: system:auth-delegator
            subjects:
              - kind: ServiceAccount
                name: vault-reviewer
                namespace: kube-system
            EOF
          when: inventory_hostname == (groups['k3s_cluster'] | first)
          changed_when: false
          become: true
    
        # 2. Récupération du JWT et du CA K3s
        - name: Retrieve vault-reviewer JWT token
          ansible.builtin.command: >-
            /usr/local/bin/k3s kubectl get secret vault-reviewer-token -n kube-system
            -o jsonpath="{.data.token}"
          register: reviewer_token_b64
          when: inventory_hostname == (groups['k3s_cluster'] | first)
          changed_when: false
          become: true
    
        - name: Read K3s server TLS CA certificate
          ansible.builtin.slurp:
            src: /var/lib/rancher/k3s/server/tls/server-ca.crt
          register: k3s_server_ca
          when: inventory_hostname == (groups['k3s_cluster'] | first)
          become: true
    
        # 3. Authentification auprès d'OpenBao via AppRole (Moindre privilège)
        - name: Authenticate to OpenBao via AppRole
          ansible.builtin.uri:
            url: "{{ openbao_url }}/v1/auth/approle/login"
            method: POST
            ca_path: "{{ openbao_ca_cert_path }}"
            body_format: json
            body:
              role_id: "{{ openbao_approle_role_id }}"
              secret_id: "{{ openbao_approle_secret_id }}"
            status_code: 200
          register: openbao_login
          delegate_to: localhost
          become: false
          run_once: true
          when: inventory_hostname == (groups['k3s_cluster'] | first)
    
        # 4. Vérification d'idempotence et activation du moteur auth/kubernetes
        - name: Check enabled auth methods in OpenBao
          ansible.builtin.uri:
            url: "{{ openbao_url }}/v1/sys/auth"
            method: GET
            headers:
              X-Vault-Token: "{{ openbao_login.json.auth.client_token }}"
            ca_path: "{{ openbao_ca_cert_path }}"
            status_code: 200
          register: openbao_auth_methods
          delegate_to: localhost
          become: false
          run_once: true
          when: inventory_hostname == (groups['k3s_cluster'] | first)
    
        - name: Enable auth/kubernetes in OpenBao if not enabled
          ansible.builtin.uri:
            url: "{{ openbao_url }}/v1/sys/auth/kubernetes"
            method: POST
            headers:
              X-Vault-Token: "{{ openbao_login.json.auth.client_token }}"
            ca_path: "{{ openbao_ca_cert_path }}"
            body_format: json
            body:
              type: "kubernetes"
              description: "Kubernetes auth for K3s cluster"
            status_code: [200, 204]
          delegate_to: localhost
          become: false
          run_once: true
          when:
            - inventory_hostname == (groups['k3s_cluster'] | first)
            - "'kubernetes/' not in (openbao_auth_methods.json.data | default(openbao_auth_methods.json))"
    
        - name: Configure Kubernetes auth engine in OpenBao
          ansible.builtin.uri:
            url: "{{ openbao_url }}/v1/auth/kubernetes/config"
            method: POST
            headers:
              X-Vault-Token: "{{ openbao_login.json.auth.client_token }}"
            ca_path: "{{ openbao_ca_cert_path }}"
            body_format: json
            body:
              kubernetes_host: "https://{{ k3s_vip }}:6443"
              kubernetes_ca_cert: "{{ k3s_server_ca.content | b64decode }}"
              token_reviewer_jwt: "{{ reviewer_token_b64.stdout | b64decode }}"
            status_code: [200, 204]
          delegate_to: localhost
          become: false
          run_once: true
          when: inventory_hostname == (groups['k3s_cluster'] | first)
    
        - name: Create or update eso-k3s role in OpenBao
          ansible.builtin.uri:
            url: "{{ openbao_url }}/v1/auth/kubernetes/role/eso-k3s"
            method: POST
            headers:
              X-Vault-Token: "{{ openbao_login.json.auth.client_token }}"
            ca_path: "{{ openbao_ca_cert_path }}"
            body_format: json
            body:
              bound_service_account_names: ["external-secrets"]
              bound_service_account_namespaces: ["external-secrets"]
              token_policies: ["eso-k3s-policy", "default"]
              audience: "https://kubernetes.default.svc.cluster.local"
              token_ttl: "1h"
            status_code: [200, 204]
          delegate_to: localhost
          become: false
          run_once: true
          when: inventory_hostname == (groups['k3s_cluster'] | first)
  ──────
  ### Phase 3 — gitops : Déploiement ESO & Déclaration des ExternalSecrets

  #### 3.1 Bootstrap ArgoCD

  1. Supprimer sops-providers.yaml et le dossier gitops/infrastructure/sops-providers/.
  2. Mettre à jour kustomization.yaml (retirer sops-providers.yaml, ajouter external-secrets.yaml).
  3. Créer gitops/bootstrap/apps/external-secrets.yaml (sync-wave -10) :
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: external-secrets
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "-10"
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: $(REPO_URL)
        path: gitops/infrastructure/external-secrets
        targetRevision: $(TARGET_REVISION)
      destination:
        server: "https://kubernetes.default.svc"
        namespace: external-secrets
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=false
          - ServerSideApply=true


  #### 3.2 Module gitops/infrastructure/external-secrets/

  • kustomization.yaml :
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    namespace: external-secrets
    components:
      - ../../components/cluster-settings
    helmCharts:
      - name: external-secrets
        repo: https://charts.external-secrets.io
        version: 2.9.0
        releaseName: external-secrets
        namespace: external-secrets
        includeCRDs: true
        valuesFile: values.yaml
    resources:
      - cluster-store.yaml
      - network-policies.yaml

  • values.yaml :
    replicaCount: 1
    serviceAccount:
      name: external-secrets
    metrics:
      service:
        enabled: true
    serviceMonitor:
      enabled: true

  • cluster-store.yaml :
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: openbao
    spec:
      provider:
        vault:
          server: "https://openbao.infra-services.local:443"
          path: "secret"
          version: "v2"
          caBundle: |
            -----BEGIN CERTIFICATE-----
            # Contenu public de ansible-services/output/openbao-ca.crt
            -----END CERTIFICATE-----
          auth:
            kubernetes:
              mountPath: "kubernetes"
              role: "eso-k3s"
              serviceAccountRef:
                name: "external-secrets"
                audiences:
                  - "https://kubernetes.default.svc.cluster.local"

  • network-policies.yaml : default-deny-all, allow-intra-namespace, egress DNS (:53), egress KubeAPI
  ($(NODES_SUBNET):6443), egress OpenBao ($(SERVICES_SUBNET):443), ingress Webhook (:10250 depuis
  $(NODES_SUBNET)), ingress Prometheus (:8080 depuis monitoring).

  #### 3.3 Remplacement des Secrets applicatifs par les ExternalSecret

  Remplacer les fichiers .sops.yaml par des *-externalsecret.yaml :

  1. gitops/infrastructure/ceph-csi/ceph-secrets-externalsecret.yaml (2 ExternalSecret : csi-rbd-secret et csi-cephfs-secret).
  2. gitops/infrastructure/cert-manager/infomaniak-externalsecret.yaml (infomaniak-api-credentials).
  3. gitops/infrastructure/external-dns/infomaniak-externalsecret.yaml (infomaniak-api-token-cluster-domain).
  4. gitops/infrastructure/observability/alertmanager-externalsecret.yaml (alertmanager-config, annotation argocd.argoproj.io/sync-wave: "-1", utilise le templating ESO pour injecter bot-token et chat-id depuis OpenBao k3s/monitoring/alertmanager-telegram dans le squelette alertmanager.yaml).
  5. gitops/infrastructure/observability/grafana-admin-externalsecret.yaml (grafana-admin-credentials, annotation argocd.argoproj.io/sync-wave: "-1").

  Structure standard d'un ExternalSecret :

    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: infomaniak-api-credentials
      namespace: cert-manager
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: openbao
        kind: ClusterSecretStore
      target:
        name: infomaniak-api-credentials
      data:
        - secretKey: api-token
          remoteRef:
            key: k3s/cert-manager/infomaniak-api-credentials
            property: api-token

  Structure avec templating (Cas Alertmanager - alertmanager-externalsecret.yaml) :

    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: alertmanager-config
      namespace: monitoring
      annotations:
        argocd.argoproj.io/sync-wave: "-1"
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: openbao
        kind: ClusterSecretStore
      target:
        name: alertmanager-config
        template:
          engineVersion: v2
          data:
            alertmanager.yaml: |
              global:
                resolve_timeout: 5m
              route:
                group_by: ["alertname", "namespace"]
                group_wait: 30s
                group_interval: 5m
                repeat_interval: 4h
                receiver: telegram
              receivers:
                - name: "null"
                - name: telegram
                  telegram_configs:
                    - bot_token: "{{ .bot_token }}"
                      chat_id: {{ .chat_id }}
                      send_resolved: true
      data:
        - secretKey: bot_token
          remoteRef:
            key: k3s/monitoring/alertmanager-telegram
            property: bot-token
        - secretKey: chat_id
          remoteRef:
            key: k3s/monitoring/alertmanager-telegram
            property: chat-id

  #### 3.4 Nettoyage SOPS

  • Supprimer gitops/.sops.yaml et les fichiers d'exemple *.sops.yaml.example.
  ──────
  ## 4. Checklists Macro d'Exécution

  ### ☑️ Checklist 1 — ansible-services : Policy AppRole & Pré-peuplement KV

  [x] Mettre à jour ansible-policy dans main.yml:320-331 pour inclure les droits sys/auth/kubernetes* et auth/kubernetes/*.
  [x] Ajouter la gestion de openbao_provision_k3s_secrets (désactivé par défaut) et openbao_k3s_secrets (liste configurable avec auto-génération et digits_only_keys) dans roles/openbao/defaults/main.yml et inventory/group_vars/all.yml.
  [x] Ajouter les tâches de pré-peuplement dynamiques dans le rôle openbao pour injecter dans secret/data/<path> (par défaut sous `k3s/`) :
      • k3s/ceph-csi-operator-system/csi-rbd-secret (userID, userKey)
      • k3s/ceph-csi-operator-system/csi-cephfs-secret (userID, userKey)
      • k3s/cert-manager/infomaniak-api-credentials (api-token)
      • k3s/external-dns/infomaniak-api-token-cluster-domain (api-token)
      • k3s/monitoring/alertmanager-telegram (bot-token, chat-id)
      • k3s/monitoring/grafana-admin-credentials (admin-user, admin-password généré ou défini)
  [x] Mettre à jour ansible-services/inventory/group_vars/all.yml.example avec les variables exemples correspondantes.
  [x] Exécuter playbook.yml et vérifier que les 6 chemins secret/data/k3s/* sont lisibles via l'UI/API OpenBao.
  ──────
  ### ☑️ Checklist 2 — ansible-k3s : Nettoyage SOPS & Auto-enregistrement via AppRole

  [x] Supprimer 08-sops-operator.yml.j2.
  [x] Mettre à jour inventory/group_vars/all.yml et all.yml.example :
      • Retirer 08-sops-operator.yml.j2 de k3s_server_manifests_templates.
      • Retirer la variable age_private_key.
      • Ajouter openbao_url, openbao_approle_role_id, openbao_approle_secret_id, openbao_ca_cert_path
      (valeurs réelles copiées en clair dans all.yml — gitignored — placeholders dans .example).
  [x] Supprimer les 2 NetworkPolicies secrets-system dans 05-network-policies.yml.j2:182-221.
  [x] Ajouter le namespace external-secrets (PSS enforce: restricted) dans 07-pod-security.yml.j2.
  [x] **Ajouter dans le rôle openbao_registration (exécuté par playbook.yml)** :
      • Création sur K3s du ServiceAccount vault-reviewer + Secret token + ClusterRoleBinding
      system:auth-delegator (via template 08-vault-reviewer.yml.j2 dans les manifests).
      • Extraction du reviewer_jwt (avec retries, peuplement asynchrone) et du server-ca.crt.
      • Login auprès d'OpenBao via AppRole ansible (POST /v1/auth/approle/login, no_log).
      • Vérification d'idempotence (GET /v1/sys/auth), activation de auth/kubernetes, configuration de
      auth/kubernetes/config et création du rôle eso-k3s via le token AppRole.
      ⚠ Correction par rapport au plan initial : champ `audience` au singulier (string) — `audiences`
      est ignoré silencieusement par l'API et casserait le TokenReview.

  ──────
  ### ☑️ Checklist 3 — gitops : Déploiement ESO & ExternalSecrets

  [x] Supprimer sops-providers.yaml et le dossier gitops/infrastructure/sops-providers/.
  [x] Mettre à jour kustomization.yaml:15 (retirer sops-providers.yaml, ajouter external-secrets.yaml).
  [x] Créer l'Application ArgoCD gitops/bootstrap/apps/external-secrets.yaml (wave -10,
  CreateNamespace=false).
  [x] Créer le module gitops/infrastructure/external-secrets/ :
      • kustomization.yaml (Helm chart external-secrets 2.9.0 — et non 0.14.3 — avec includeCRDs: true).
      • values.yaml (serviceAccount.name: external-secrets, metrics / ServiceMonitor activés).
      • cluster-store.yaml (ClusterSecretStore openbao avec caBundle public et audience
      https://kubernetes.default.svc.cluster.local).
      • network-policies.yaml (règles de flux réseau strictes ; webhook :10250 depuis NODES_SUBNET et
      PODS_SUBNET — nouvelle var cluster-settings — car 3 apiservers HA host-gw : source variable).
  [x] Remplacer les .sops.yaml par les ExternalSecret dans ceph-csi, cert-manager, external-dns et
  observability (avec templating pour alertmanager-config).
      • Suppression complète de cloudflare et ovh : dns-credentials.sops.yaml, blocs solvers commentés
      dans cluster-issuers.yaml, helmChart cert-manager-webhook-ovh commenté.
  [x] Nettoyer les résidus SOPS : supprimer gitops/.sops.yaml et les fichiers *.sops.yaml.example.
  [x] Documentation alignée (README racine, ansible-k3s/README.md, gitops/README.md, commentaires
  kps-values.yaml) — avancée par rapport à la checklist 4/étape 5.
  ──────
  ### ☑️ Checklist 4 — Déploiement & Validation End-to-End

  [ ] Étape 1 : Lancer ansible-services/playbook.yml → vérifier le peuplement KV dans OpenBao.
  [ ] Étape 2 : Lancer iac-k3s (provisioning des VMs K3s).
  [ ] Étape 3 : Lancer ansible-k3s/playbook.yml → valider le déploiement K3s et l'auto-enregistrement
  OpenBao via AppRole.
  [ ] Étape 4 : Vérifier ArgoCD et ESO :
      • kubectl get clustersecretstore openbao → statut Valid.
      • kubectl get externalsecret -A → tous en statut Ready (SecretSynced).
      • Vérifier la bonne santé des applications consommatrices (login Grafana, routage ExternalDNS,
      certificats Cert-Manager, volumes Ceph CSI).
  [ ] Étape 5 : Mettre à jour la documentation (README.md racine, ansible-k3s/README.md, gitops/README.
  md).