# NAWEX Onboarding — Your First Week

Welcome. This guide gets a new engineer from "just cloned the repo" to
"making reviewed changes in a dev overlay" inside a week. It is deliberately
action-oriented: every section ends with something you *do*, not just read.

For the conceptual framing of each layer, pair this guide with the top-level [README](../README.md) and the [platform-operations-reference.md](platform-operations-reference.md).

---

## Before You Start

You'll be more productive if you understand these three things up front:

1. **NAWEX is a hybrid platform.** Bare metal (Cisco / HPE / Dell), vSphere, AWS, and Azure are peer targets behind one control plane. You will touch all four at some point. Do not assume cloud-only defaults.
2. **GitOps is the contract.** Anything in production got there because a Git commit was reviewed, merged, and reconciled by Argo CD. Manual `kubectl apply` against prod is not a workflow — it is an incident.
3. **Prod is gated.** Dev, staging, and onprem auto-sync. Prod's Argo CD application runs with `automated: false` for `prune` and `selfHeal` — changes require an explicit sync. Know this before you ask why your merge didn't appear.

---

## Day 0 — Before Monday

### Access you'll need

Your manager / onboarding buddy will arrange these. Confirm you have working access before Day 1:

- **SCM** — GitHub or GitLab, whichever this repo is hosted on. Push access to non-prod branches; PR access to all.
- **Slack** — the NAWEX alerts channel plus the team channel. The alerts channel is how you'll hear about incidents.
- **Cloud** — read-only AWS and Azure at minimum; `terraform plan` access to dev; stronger rights arrive later.
- **vCenter** — read-only is enough for Day 1. Write access comes with on-call rotation.
- **Argo CD UI** — SSO login to the dev/staging cluster's Argo CD.
- **Grafana / Prometheus** — read access to the platform dashboards.

### Local tools

Install and confirm each:

| Tool | Version floor | Quick check |
|------|---------------|-------------|
| git | 2.40+ | `git --version` |
| docker | 24+ | `docker run --rm hello-world` |
| kubectl | 1.28+ | `kubectl version --client` |
| kind | 0.22+ | `kind version` |
| kustomize | 5+ | `kustomize version` |
| terraform | 1.7+ | `terraform version` |
| ansible | 9+ | `ansible --version` |
| python | 3.11+ | `python --version` |
| argocd CLI | 2.10+ | `argocd version --client` |
| pre-commit | latest | `pre-commit --version` |

### Clone and lint

```bash
git clone <repo-url> nawex-hybrid-devops-platform
cd nawex-hybrid-devops-platform

pip install pre-commit && pre-commit install

# Same checks CI runs — should pass on a clean tree
pip install ruff pytest -r app/nawex-api/requirements.txt -r finops-aiops/python/requirements.txt
ruff check . && ruff format --check . && pytest -q

# Validate every overlay renders
for o in k8s/overlays/*; do kustomize build "$o" >/dev/null; done
```

If anything here fails on `main`, tell your onboarding buddy — it means either your tooling is off-version or `main` is broken.

**Done with Day 0 when:** every command above succeeds on a clean clone.

---

## Day 1 — Run the Platform Locally

### Read first (30 minutes, no commands yet)

1. [README.md](../README.md) — the architecture diagram is the one picture you'll reference all year. Print it if that helps.
2. [architecture/platform-operations-reference.md](platform-operations-reference.md) — skim the sections on the layers you'll touch first. Deep reading comes later.
3. [runbooks/troubleshooting.md](../runbooks/troubleshooting.md) — skim the layer headings. You'll come back to this later in the week when something breaks.

### Spin up the local GitOps harness

This creates a `kind` cluster, installs Argo CD, snapshots your workspace into a local bare Git repo, and lets Argo CD reconcile the sample workload from it:

```bash
./scripts/start_local_gitops.sh

# In another terminal, expose Argo CD and the sample API
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
kubectl port-forward svc/nawex-api -n nawex-local 8081:80 &

# Validate
./scripts/smoke_test.sh

# When you're done
./scripts/stop_local_gitops.sh
```

While this is running, open `https://localhost:8080` and log in to Argo CD (the initial admin password is in `argocd-initial-admin-secret` — see [gitops/local/](../gitops/local/)). Find the `local-platform` app and click through its child resources until you can trace the Deployment → Pod → Service relationship yourself.

**Done with Day 1 when:** you can explain, out loud, what each of `start_local_gitops.sh`'s steps does (cluster, image build, Git snapshot, Argo CD install, app sync). If you can't, re-read the script.

---

## Day 2 — Make Your First Change

Pick a tiny, visible change. Good first-PR candidates:

- Add a log line to [app/nawex-api/](../app/nawex-api/).
- Tighten a default in a Kustomize overlay (e.g. bump replicas on `k8s/overlays/dev/`).
- Fix a typo in a runbook.

### The full cycle

1. **Branch.** `git checkout -b yourname/first-change`.
2. **Change.** Make the smallest thing that tests the whole pipeline.
3. **Local gates.** Re-run the Day 0 checks. `pre-commit run --all-files` is the one-liner.
4. **Commit.** Conventional-style message preferred (`fix(api): …`, `docs(runbooks): …`).
5. **Push + PR.** Let CI run. Read the logs of *every* stage, even the green ones — build a mental model of what each gate is checking.
6. **Review.** Expect at least one round of comments; this is how you calibrate to the team's taste.
7. **Merge.** Watch Argo CD reconcile the change into dev. The round trip from merge to "running in dev" is normally under two minutes; if it's longer, [runbooks/troubleshooting.md § GitOps](../runbooks/troubleshooting.md#5--gitops-delivery-argo-cd).

**Done with Day 2 when:** your change is live in dev and you can show it in the live cluster with `kubectl` or by hitting the endpoint.

---

## Days 3–5 — Touch Every Layer

One concrete exercise per layer. Don't just read — run the command, read the output, understand it:

### Terraform

```bash
cd infra/terraform/envs/dev
terraform init -backend=false
terraform validate
terraform plan   # read the plan; do NOT apply
```

Answer: what would happen if you applied this plan on a fresh account?

### Ansible + Linux baseline

```bash
ansible-playbook infra/ansible/playbooks/linux-baseline.yml --syntax-check
ansible-inventory -i infra/ansible/inventories/dev/hosts.yml --list
```

Read [infra/ansible/docs/baseline-explained.md](../infra/ansible/docs/baseline-explained.md). Answer: which of the four roles (`system`, `security`, `observability`, `docker`) would touch SSH config, and what specifically does it change?

### Kubernetes overlays

```bash
kustomize build k8s/overlays/dev/   | less
kustomize build k8s/overlays/openshift/ | grep -i 'route\|scc'
```

Answer: what's different between the `dev` and `openshift` overlays? (Hint: Route, SCC, PSA labels.)

### GitOps

```bash
argocd app list
argocd app get <dev-app>
argocd app diff <dev-app>
```

Answer: what does the `AppProject` in [gitops/project.yaml](../gitops/project.yaml) *allow*, and why no wildcards?

### Observability

Reproduce an alert locally. Pick a simple rule from [observability/alerts/slo-alerts.yml](../observability/alerts/slo-alerts.yml) (e.g. high error rate). In the local kind cluster, generate the condition (kill a pod, force a 500) and watch the alert fire in Prometheus. You don't need Slack for this exercise.

### FinOps / AIOps

```bash
# From repo root — use --help on each to see the real flags
python -m finops_aiops.rightsizing --help
python -m finops_aiops.anomaly --help
```

Run one against local or cached data. Read the output. Answer: what is the difference between "rightsizing" and "anomaly" in this platform — not generally, but specifically in the code here?

### Migration

Read [migration/samples/](../migration/samples/). Generate a container from a sample WorkloadProfile:

```bash
python -m migration.containerize --profile migration/samples/<profile>.yaml --out /tmp/out
docker build /tmp/out
```

**Done with Days 3–5 when:** you've run each of the seven exercises above and can describe, in one sentence, what each layer is responsible for.

---

## Conventions You'll Be Held To

These are the non-obvious ones. The obvious ones (don't force-push, don't skip tests) you already know.

- **No `kubectl apply` against prod.** Ever. Argo CD is the only writer.
- **No `--no-verify` on git.** If a hook fails, fix the underlying issue.
- **No secrets in code.** `.env` is gitignored; committed configs reference env vars. Cloud creds go through the CI secret store, not files.
- **No wildcard AppProject roles.** If Argo CD can't deploy a resource kind, add the kind to the project with intent — don't replace with `*`.
- **No PSA downgrade.** Namespaces are PSA `restricted`. Workloads meet the bar (`runAsNonRoot`, `seccompProfile: RuntimeDefault`, dropped caps, `readOnlyRootFilesystem`). Fix the workload, not the namespace.
- **CI is the truth.** A change is not "done" until CI is green. "Works on my machine" does not ship.
- **Prod deploys are explicit.** `automated: false` on prod is intentional — someone signs off.
- **Feature flags over forks.** Don't maintain parallel branches; flag the new behavior and roll forward.
- **Commit messages explain *why*.** The *what* is in the diff.

See also: [security posture](../README.md#security-posture), [CIS checklist](../infra/ansible/compliance/cis-checklist.md).

---

## Where to Ask

Escalation ladder, in order:

1. **Your onboarding buddy.** Anything in your first two weeks, default to them.
2. **Team Slack channel.** Best for questions others might have, or might answer faster than your buddy.
3. **Platform alerts channel.** Only for things that look like an active incident.
4. **On-call.** Only when the alert channel tells you to page — never cold-page on day 1.
5. **Runbooks.** [runbooks/troubleshooting.md](../runbooks/troubleshooting.md) first (the triage matrix is designed for "I don't know where to look"), then the specific runbook for your symptom.

Asking a dumb question in your first month is fine. Asking the same question twice is a signal you need to write it down — ideally as a PR to a runbook.

---

## Further Reading

In the order you should read them, roughly one per week after week 1:

1. [architecture/platform-operations-reference.md](platform-operations-reference.md) — day-2 operations reference.
2. [architecture/sli-slo-model.md](sli-slo-model.md) — what we measure and why.
3. [runbooks/troubleshooting.md](../runbooks/troubleshooting.md) — re-read now that you know the layers.
4. [infra/ansible/docs/baseline-explained.md](../infra/ansible/docs/baseline-explained.md) — why baseline-as-code.
5. [runbooks/slack-alerting.md](../runbooks/slack-alerting.md) — the approve/deny flow you'll use when you take on-call.

---

## Onboarding Checklist

Print this or paste into your 1:1 doc. Tick items as you go.

- [ ] Day 0: access confirmed (SCM, Slack, cloud, vCenter, Argo CD, Grafana)
- [ ] Day 0: every tool from the table above installed and version-checked
- [ ] Day 0: `ruff`, `pytest`, and all seven `kustomize build` pass on a clean `main`
- [ ] Day 1: read the three docs listed in Day 1
- [ ] Day 1: `start_local_gitops.sh` + `smoke_test.sh` succeed end-to-end
- [ ] Day 1: can explain each step of the local harness out loud
- [ ] Day 2: first PR merged, visible in dev via `kubectl` or endpoint
- [ ] Day 3–5: ran the seven layer exercises; can describe each layer in one sentence
- [ ] Week 1: read the conventions list and know which one will bite you first
- [ ] Week 1: know your escalation ladder and the name of your onboarding buddy
