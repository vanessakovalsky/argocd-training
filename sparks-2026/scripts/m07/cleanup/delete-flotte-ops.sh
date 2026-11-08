#!/usr/bin/env bash
# Remove the M07 supervision tools (webhook receiver, Prometheus) and notification settings.
set -eu
kubectl delete namespace flotte-ops --ignore-not-found
kubectl patch cm argocd-notifications-cm -n argocd --type merge -p \
  '{"data":{"service.webhook.flotte-alertes":null,"template.flotte-webhook":null,"trigger.flotte-deployed":null,"trigger.flotte-degraded":null}}'
echo "M07 supervision objects removed"
