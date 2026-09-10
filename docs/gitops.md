# Terraform + ArgoCD -- ownership split and a real round trip

`terraform/` and `k8s/` both touch the monitoring stack, but they do not
manage the same objects. This document says exactly who owns what, why, and
proves the sync loop actually works with a real edit that shipped through it.

## Why not let Terraform manage everything

Terraform reconciling `k8s/`'s Deployment/Service/ConfigMap objects
*and* ArgoCD's `selfHeal` reconciling the same objects from the same git
repo would fight each other: `terraform apply` and ArgoCD would each try to
own the same resource's desired state, and whichever ran last would win
until the other ran again. The split used here is the one real platform
teams use to avoid exactly that:

- **Terraform owns the platform layer**: the `network-lab` and `argocd`
  namespaces, installing ArgoCD itself, and the ArgoCD `Application` custom
  resource that tells ArgoCD what to sync and from where
  (`terraform/namespace.tf`, `terraform/argocd.tf`,
  `terraform/application.tf`).
- **ArgoCD owns the application layer**: once the `Application` resource
  exists, ArgoCD reads `k8s/`'s Deployment/Service/ConfigMap manifests
  straight out of this git repo and reconciles the cluster to match them.
  Those manifests are not duplicated into Terraform -- there is exactly one
  place (`k8s/`) that defines what the monitoring stack looks like.

## A real Terraform limitation, not hidden

Terraform's `kubernetes_manifest` resource (`hashicorp/kubernetes` provider)
validates a custom resource's schema against its CRD *at plan time*. That
means the `Application` CRD has to already exist in the cluster before
Terraform can even plan `application.tf`'s resource -- a fresh cluster
cannot `terraform apply` all three `.tf` files in one pass.

`argocd.tf` installs ArgoCD (and its CRDs, including `Application`) via a
`null_resource`/`local-exec` running `terraform/scripts/wait-for-rollout.sh`,
not as typed `kubernetes_manifest` resources -- ArgoCD's upstream install
manifest spans several thousand lines across dozens of unrelated resource
kinds (CRDs, ClusterRoles, Deployments, a StatefulSet, NetworkPolicies); hand
-transcribing that into `.tf` blocks would not make it more real Terraform,
just more YAML pasted into `.tf` files with none of Terraform's own
diffing/planning behavior actually engaged. Terraform still owns *when* it
runs and blocks apply until ArgoCD is genuinely healthy (the script waits on
three separate rollout-status checks), which is the part that matters.

Practical consequence: this extension applies in two passes.

```
terraform apply   # namespaces + ArgoCD install (blocks until healthy)
terraform apply   # the Application CR, now that its CRD exists
```

A single `terraform apply` on a fresh cluster fails the second resource with
a schema-lookup error on the first pass, then succeeds on the second --
verified directly while building this extension (see
`projects/network-lab/plan.md`, Extension F Step 2's "Actually shipped"
note in the `cvs` repo for the exact sequence).

## A second real fix: the CRD-size annotation limit

`kubectl apply`'s default client-side apply writes the whole manifest into a
`kubectl.kubernetes.io/last-applied-configuration` annotation, capped at
256KiB by Kubernetes itself. ArgoCD's `applicationsets.argoproj.io` CRD
alone exceeds that. The install script uses
`kubectl apply --server-side --force-conflicts` instead, which tracks field
ownership server-side and has no such limit.

## Proof the sync loop actually works: a real round trip

Registering an `Application` once and taking a screenshot of a green
checkmark proves nothing about whether the sync loop keeps working. This
extension proved it with a real change:

1. `k8s/snmp-exporter-deployment.yaml` had no CPU/memory `requests` or
   `limits` -- added real ones (`25m`/`32Mi` requests, `100m`/`64Mi`
   limits), a genuine right-sizing change.
2. Committed and pushed to `main` (`cb2c90c`).
3. Triggered a sync (`kubectl patch application network-lab-monitoring -n
   argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'`)
   rather than waiting out the default ~3-minute auto-sync poll.
4. `kubectl get application network-lab-monitoring -n argocd -o
   jsonpath='{.status.sync.revision}'` returned
   `cb2c90c54896e36f5a5ffa4c377415a0f4546fe1` -- the exact commit SHA just
   pushed, confirmed against `git log -1 --format=%H` in the same
   terminal.
5. `kubectl get deploy snmp-exporter -n network-lab -o
   jsonpath='{.spec.template.spec.containers[0].resources}'` showed the
   exact `requests`/`limits` just committed, live on the cluster.

That is the actual claim this extension makes: a git commit reaches a
running pod's spec with no `kubectl apply` in between.
