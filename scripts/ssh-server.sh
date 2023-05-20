#!/bin/sh

# Copy authorized_keys
cp /opt/Dockovpn_data/ssh_authorized_keys /home/sshuser/.ssh/authorized_keys

# Start the background application in the background
/usr/sbin/sshd &

# Wait for the background application to start (if needed)
sleep 5

# Execute the main command or executable specified in CMD
exec "$@"
