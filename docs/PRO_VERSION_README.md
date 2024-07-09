# EZ-Plesk-Transfer-Bridge-Pro

## Overview

EZ-Plesk-Transfer-Bridge-Pro is an advanced bash script for migrating Plesk domains between servers using a bridge (intermediary) server. This version includes additional features for more complex migration scenarios.

## Features

All features of the Basic version, plus:

- Configuration file support
- Dry run mode
- SSL certificate migration
- Verbose logging
- Component-specific migration options

## Prerequisites

- A Linux-based bridge server with bash
- SSH access to both source and target Plesk servers
- Sufficient disk space on all servers for domain backups

## Usage

1. Copy the script and configuration file template to your bridge server.
2. Make the script executable:
   chmod +x EZ-Plesk-Transfer-Bridge-Pro.sh
3. (Optional) Edit the configuration file (`Pro-Config.conf`) with your server details.
4. Run the script:

### Command-line Options

- `--dry-run`: Simulate the migration process without making changes
- `--config <file>`: Specify a custom configuration file
- `--migrate-ssl`: Include SSL certificate migration
- `--components <list>`: Specify components to migrate (e.g., "files,databases,mail")
- `--verbose`: Enable verbose logging

## Script Workflow

1. Parse command-line arguments and read configuration file (if provided)
2. Gather or confirm source and target server information
3. Verify SSH connections to both servers
4. Check Plesk versions on both servers
5. For each domain to be migrated:

- Verify domain existence on source server
- Check if domain already exists on target server
- Create a backup of the domain on the source server
- Transfer the backup to the target server
- Restore the backup on the target server
- Migrate SSL certificate if option is enabled
- Clean up temporary files

## Configuration File

The configuration file (`Pro-Config.conf`) can include the following settings:

- Server details (IPs, ports, usernames, passwords)
- Default options (SSL migration, etc.)
- Component migration preferences

## Logging

The script generates a detailed log file in the `logs` directory, named `transfer_bridge_YYYYMMDD_HHMMSS.log`.

## Advanced Features

- **Dry Run Mode**: Simulates the migration process without making actual changes.
- **SSL Migration**: Transfers and installs SSL certificates for migrated domains.
- **Verbose Logging**: Provides detailed information about each step of the migration process.

## Troubleshooting

- Use the `--verbose` option for detailed logging
- Check the configuration file for correct server details
- Verify sufficient disk space and permissions on all servers

## Security Considerations

- The script uses password-based authentication by default
- Configuration files may contain sensitive information and should be secured
- Backup files, including SSL certificates, are temporarily stored on the bridge server

For any issues or feature requests, please visit the [GitHub issues page](https://github.com/LazyQuad/EZ-Plesk-Transfer-Bridge/issues).
