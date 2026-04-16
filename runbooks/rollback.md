# Rollback

1. Freeze further deploys and pause automatic promotion if needed.
2. Identify the last known good Git revision for the affected environment overlay.
3. Revert the manifest or configuration change in Git.
4. Allow Argo CD to resync or trigger a manual sync if policy requires it.
5. Re-run smoke tests and confirm the service returns to budget-safe behavior.
