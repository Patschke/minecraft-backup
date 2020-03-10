# Minecraft Backup
Backup script for Linux servers running a Minecraft server in a Docker Container (or using RCON)

### Disclaimer
Backups are essential to the integrity of your Minecraft world. You should automate regular backups and **check that your backups work**. While this script has been used in production for several years, it is up to you to make sure that your backups work and that you have a reliable backup policy.

Please refer to the LICENSE (MIT License) for the full legal disclaimer.

## Features
- Create backups of your world folder
- Manage deletion of old backups
  - "thin" - keep last 24 hourly, last 30 daily, and use remaining space for monthly backups
  - "sequential" - delete oldest backup
- Choose your own compression algorithm (tested with: `gzip`, `xz`, `zstd`)
- Able to print backup status and info to the Minecraft chat

## Requirements
- Linux computer (tested on Ubuntu)
- Your Minecraft server needs to be running in a Docker container or have an RCON port open at localhost. 
- In case of using RCON: MCRCON builded, installed and in PATH. See https://github.com/tiiffi/mcrcon for more info. 
- In case of using Docker: permissions to exec into the container
- Minecraft server (tested with docker image from itzg/minecraft-server) with local mounted data directory

## Installation
1. Download the script: `$ wget https://raw.githubusercontent.com/knifesk/minecraft-backup/master/backup.sh`
2. Mark as executable: `$ chmod +x backup.sh`
3. Use the command line options or configure default values at the top of `backup.sh`:

Command line options:
```text
-a    Compression algorithm (default: gzip)
-c    Enable chat messages
-d    Delete method: thin (default), sequential, none
-e    Compression file extension, exclude leading "." (default: gz)
-f    Output file name (default is the timestamp)
-h    Shows this help text
-i    Input directory (path to world folder)
-l    Compression level (default: 3)
-m    Maximum backups to keep, use -1 for unlimited (default: 128)
-n    Name of DOCKER CONTAINER. This overrides usage of RCON PASS, RCON PORT. 
-o    Output directory
-p    Prefix that shows in Minecraft chat (default: Backup)
-q    Suppress warnings
-r    Minecraft server RCON PASSWORD
-s    Minecraft server RCON PORT
-v    Verbose mode
```

Example usage of command line options with RCON:
```bash
./backup.sh -c -i /home/server/minecraft-server -o /mnt/external-storage/minecraft-backups -r MyRconPassword -s 25575
```
This will use show chat messages (`-c`) in the server with RCON port 25575 and save a backup of `/home/server/minecraft-server` into `/mnt/external-storage/minecraft-backups` using the default thinning delete policy for old backups.

Example usage of command line options with Docker:
```bash
./backup.sh -c -i /my/nice/server/data/world/ -n mc -o /my/external/server/backup/
```
This will use show chat messages (`-c`) in the server running in Docker container mc and save a backup of `/my/nice/server/data/world/` into `/my/external/server/backup/` using the default thinning delete policy for old backups.

4. Create a cron job to automatically backup:
    - Edit the crontab: `$ crontab -e`
    - Example for hourly backups: `00 * * * * /path/to/backup.sh`

## Retrieving Backups
Always test your backups! Backups are in the `tar` format and compressed depending on the option you choose. To restore, first decompress if necessary and then extract using tar. You may be able to do this in one command if `tar` supports your compression option, as is the case with `gzip`:

Example:
```bash
mkdir restored-world
cd restored-world
tar -xzvf /path/to/backups/2019-04-09_02-15-01.tar.gz
```

Then you can move your restored world (`restored-world` in this case) to your Minecraft server folder and rename it (usually called `world`) so the Minecraft server uses it.

## Help
- Make sure the compression algorithm you specify is installed on your system. (zstd is not installed by default)
- Make sure your compression algorithm is in the crontab's PATH
- Make sure cron has permissions for all the files involved and access to RCON/Docker
- It's surprising how much space backups can take--make sure you have enough empty space
- `SERVER_DIRECTORY` should be the local mounted directory you wish to backup
- Do not put trailing `/` in the `SERVER_DIRECTORY` or `BACKUP_DIRECTORY`
- If "thin" delete method is behaving weirdly, try emptying your backup directory or switch to "sequential"
