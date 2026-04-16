# Slack Alerting + Incident Response

End-to-end flow for engineers receiving an alert in Slack.

## Pipeline

```
Prometheus rules  ──►  AlertManager  ──►  Slack channel
(slo-alerts.yml)       (alertmanager.yml + slack.tmpl)
                             │
                             └─►  alert_webhook.py  ──►  .incidents/<id>.json
                                                                │
                                                                ▼
                                                   scripts/incident_respond.sh
                                                   ├── list
                                                   ├── show    <id>
                                                   ├── approve <id>  → scripts/remediations/<action>.sh
                                                   └── deny    <id>
```

## What an alert looks like in Slack

Each Slack message includes:

- Severity and service labels
- Human-readable summary + description
- A direct link to the matching runbook
- The `remediation_action` that will run on approval
- A **copy-ready command block** with `approve`, `deny`, and `show` commands

Example rendered message body:

> :rotating_light: *[CRITICAL] NawexApiFastBurn*
>
> *Service:* `nawex-api`  *Severity:* `critical`
> *Summary:* nawex-api burning error budget ~14x (1h window)
>
> nawex-api 5xx rate is exhausting the 99.9% availability budget fast. Likely cause:
> a bad deploy or an upstream dependency. The remediation action `rollback_last_deploy`
> triggers an Argo CD rollback to the previously healthy revision.
>
> *Runbook:* https://.../runbooks/rollback.md
> *Remediation action:* `rollback_last_deploy`
>
> *Approve / deny from any terminal with kube access:*
> ```
> ./scripts/incident_respond.sh approve 3f1a9b2c   # run the remediation
> ./scripts/incident_respond.sh deny    3f1a9b2c   # silence and acknowledge
> ./scripts/incident_respond.sh show    3f1a9b2c   # preview the plan first
> ```

## What to do on receipt

1. **Read the summary.** Confirm the incident matches what you're seeing in dashboards.
2. **Open the runbook link** embedded in the alert — it has the full procedure.
3. **Run `show <id>` first.** This prints the incident JSON and executes the mapped
   remediation in `DRY_RUN=1` mode so you can see exactly what `approve` would do.
4. **Decide:**
   - If the evidence matches a textbook case — approve. The remediation script is
     idempotent and the audit trail posts back to Slack.
   - If the signal looks spurious or you need more time — deny. This acknowledges
     the incident and silences repeat fires until you clear the state file.

## Remediation mapping

| `remediation_action`      | Script                                         | What it does                                   |
| ------------------------- | ---------------------------------------------- | ---------------------------------------------- |
| `rollback_last_deploy`    | `scripts/remediations/rollback_last_deploy.sh` | `kubectl rollout undo` for the affected deploy |
| `investigate_slo_burn`    | `scripts/remediations/investigate_slo_burn.sh` | Scale +1 replica, tail recent error logs       |
| `worker_heap_profile`     | `scripts/remediations/worker_heap_profile.sh`  | Capture process snapshot, restart worker pod   |
| `scale_down_offhours`     | `scripts/remediations/scale_down_offhours.sh`  | Reduce worker replicas outside business hours  |
| `reduce_requests`         | `scripts/remediations/reduce_requests.sh`      | Print a review-first patch (never auto-applies)|

All remediation scripts honor `DRY_RUN=1` and take `--incident <path>`.

## Local end-to-end test (no real Prometheus needed)

```bash
# 1. Start the webhook receiver in a separate terminal.
python scripts/alert_webhook.py --host 127.0.0.1 --port 9099

# 2. Simulate an AlertManager webhook POST.
curl -sS -X POST http://127.0.0.1:9099/alerts \
  -H 'Content-Type: application/json' \
  -d @observability/alertmanager/examples/sample-alert.json

# 3. Triage it.
./scripts/incident_respond.sh list
./scripts/incident_respond.sh show    <fingerprint>
DRY_RUN=1 ./scripts/incident_respond.sh approve <fingerprint>
./scripts/incident_respond.sh deny    <fingerprint>
```

## Slack wiring

1. Create an incoming webhook in Slack (`https://api.slack.com/messaging/webhooks`)
   and copy the URL.
2. Store it as an env var / K8s secret:
   - Local: `cp .env.example .env && $EDITOR .env`
   - CI: add `SLACK_WEBHOOK_URL` as a GitHub Actions secret
   - Cluster: create a secret named `alertmanager-slack` with key `url`
3. AlertManager expands `${SLACK_WEBHOOK_URL}` from its environment on start.
