#!/bin/bash
# KZ

# Check for required dependencies
command -v cdparanoia >/dev/null 2>&1 || { echo "[-] 'cdparanoia' is not installed. Please install it."; exit 1; }
command -v eject >/dev/null 2>&1 || { echo "[-] 'eject' is not installed. Please install it."; exit 1; }

read -p "[+] Enter the folder in the current directory where you want to rip the audio CD: " folder_name

if ! mkdir -p "$folder_name"; then
    echo "[-] Failed to create directory '$folder_name'. Check permissions and try again."
    exit 1
fi

echo "[+] Created directory: '$folder_name'."

cd "$folder_name" || { echo "[-] Failed to change directory to '$folder_name'."; exit 1; }
echo "[+] Changed directory to '$folder_name'."

# Check if the audio CD is ready, with up to 3 attempts
max_attempts=3
attempt=1
while ! cdparanoia -Q >/dev/null 2>&1; do
    echo "[-] Attempt $attempt: No audio CD found or the CD is not ready."
    if (( attempt == max_attempts )); then
        echo "[-] Failed to detect an audio CD after $max_attempts attempts. Exiting."
        cd ..
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 10
done
echo "[+] Audio CD is ready."

# Rip the audio CD
echo "[+] Running 'cdparanoia -B' to rip the audio CD..."
if cdparanoia -B; then
    echo "[+] Audio CD ripped successfully."
else
    echo "[-] Failed to rip the audio CD. Check the CD and try again."
    cd ..
    exit 1
fi

cd ..
echo "[+] Returned to the parent directory."

if eject; then
    echo "[+] Done"
else
    echo "[-] Failed to eject the CD. You may need to eject it manually."
fi
