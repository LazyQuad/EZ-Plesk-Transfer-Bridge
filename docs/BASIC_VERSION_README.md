# EZ-Plesk-Transfer-Bridge-Basic

## Overview

EZ-Plesk-Transfer-Bridge-Basic is a streamlined bash script for migrating Plesk domains between servers using a bridge (intermediary) server. This script covers essential functionality for basic migration needs.

## Features

- SSH connection verification
- Plesk version checking
- Domain existence validation
- Domain backup and restore
- Basic error handling and logging

## Prerequisites

- A Linux-based bridge server with bash
- SSH access to both source and target Plesk servers
- `sshpass` installed on the bridge server
- Sufficient disk space on all servers for domain backups

## Usage

1. Copy the script to your bridge server.
2. Make the script executable:
   chmod +x EZ-Plesk-Transfer-Bridge-Basic.sh
3. Run the script:
   ./EZ-Plesk-Transfer-Bridge-Basic.sh
4. Follow the interactive prompts to provide server details and domain information.

## Script Workflow

1. Gather source and target server information
2. Verify SSH connections to both servers
3. Check Plesk versions on both servers
4. For each domain to be migrated:

- Verify domain existence on source server
- Check if domain already exists on target server
- Create a backup of the domain on the source server
- Transfer the backup to the target server
- Restore the backup on the target server
- Clean up temporary files

## Logging

The script generates a log file in the same directory, named `migration_YYYYMMDD_HHMMSS.log`, containing detailed information about the migration process.

## Limitations

- Uses password-based SSH authentication
- Does not support SSL certificate migration
- No dry-run mode
- Limited error recovery options

## Troubleshooting

- Ensure `sshpass` is installed on the bridge server
- Verify SSH credentials for both source and target servers
- Check that Plesk is properly installed on both servers
- Ensure sufficient disk space on all servers

## Security Considerations

- The script uses password-based authentication, which may not be suitable for all environments
- Ensure the bridge server is properly secured, as it will have access to both source and target servers
- Temporarily stored backup files may contain sensitive information

For any issues or feature requests, please visit the [GitHub issues page](https://github.com/LazyQuad/EZ-Plesk-Transfer-Bridge/issues).
