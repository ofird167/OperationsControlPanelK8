with open('scripts/bootstrap.sh', 'r') as f:
    content = f.read()

content = content.replace('--set configuration.backupStorageLocation.name=default', '--set configuration.backupStorageLocation[0].name=default')
content = content.replace('--set configuration.backupStorageLocation.bucket=${GCS_BACKUP_BUCKET}', '--set configuration.backupStorageLocation[0].bucket=${GCS_BACKUP_BUCKET}')
content = content.replace('--set configuration.backupStorageLocation.provider=gcp', '--set configuration.backupStorageLocation[0].provider=gcp')
content = content.replace('--set configuration.provider=gcp', '--set configuration.backupStorageLocation[0].provider=gcp')

with open('scripts/bootstrap.sh', 'w') as f:
    f.write(content)
