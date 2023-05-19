#!/bin/sh

# Start the background application in the background
/usr/sbin/sshd &

# Wait for the background application to start (if needed)
sleep 5

# Execute the main command or executable specified in CMD
exec "$@"
