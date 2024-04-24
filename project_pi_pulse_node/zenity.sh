#!/bin/bash

# Define the script directory and source functions
script_dir=$(dirname "$0")
source "$script_dir/functions.sh"

# Path to original image
original_image="/home/barchef/Desktop/pulse-node/project_pi_pulse_node/PP.png"
# Path to resized image
resized_image="/home/barchef/Desktop/pulse-node/project_pi_pulse_node/PP_resized.png"

# Resize the image using ImageMagick
convert "$original_image" -resize 200x200 "$resized_image"

# Initial information dialog with YAD
yad --title "PulseChain Validator Node Setup" \
    --image="$resized_image" --image-on-top \
    --text "PulseChain Validator Node Setup by Project Pi\n\nPlease press OK to continue." \
    --button=gtk-ok:0 --buttons-layout=center --geometry=530x10+800+430

# Check if the user pressed OK
if [[ $? -ne 0 ]]; then
    yad --window-icon=error --title "Setup Aborted" \
        --text "Setup aborted by the user." \
        --button=gtk-ok:0 --buttons-layout=center --geometry=300x200+100+100
    exit 1
fi


# Create users if they do not exist and add them to the docker group
# Create users if they do not exist and add them to the docker group
for user in geth erigon lighthouse; do
    if ! id "$user" &>/dev/null; then
        sudo useradd -m -s /bin/bash $user
        sudo usermod -aG docker $user
        echo "User $user created and added to docker group."
        # Check if user can now access Docker
        if sudo -u $user docker info &>/dev/null; then
            echo "User $user can now access Docker."
        else
            echo "User $user cannot access Docker. They need to log out and back in or you need to restart this script."
        fi
    else
        if ! sudo -u $user docker info &>/dev/null; then
            sudo usermod -aG docker $user
            echo "User $user was already created but is now added to the Docker group."
            echo "Please ensure $user logs out and back in or restart this script."
        fi
    fi
done

# Function to check if a user can access Docker
can_access_docker() {
    local user=$1
    if sudo -u $user docker info &>/dev/null; then
        echo "User $user can access Docker."
        return 0
    else
        echo "User $user cannot access Docker. Attempting to add to Docker group..."
        sudo usermod -aG docker $user
        if sudo -u $user docker info &>/dev/null; then
            echo "User $user can now access Docker after being added to the group."
        else
            echo "Failed to grant Docker access to user $user. Please ensure the Docker service is running and the user is logged out and back in."
        fi
        return 1
    fi
}

# Function to safely execute Docker commands
execute_docker_command() {
    local cmd="$1"
    local user="$(echo "$cmd" | grep -oP '(?<=sudo -u ).+?(?= docker)')"
    local container_name="$(echo "$cmd" | grep -oP '(?<=--name ).+?(?= -v)')"

    # Ensure the user can run Docker commands
    sudo usermod -aG docker $user

    # Check if the container exists
    if docker ps -a | grep -q "$container_name"; then
        echo "Removing existing container $container_name"
        sudo -u $user docker rm -f $container_name
    fi

    # Run the Docker command
    eval "$cmd"
}

# Network choice using Zenity
network_choice=$(zenity --list --width=300 --height=200 --title="Choose Network" \
                        --text="Select the network for the node setup:" \
                        --radiolist --column="Select" --column="Network" \
                        FALSE "Mainnet" FALSE "Testnet")
if [ -z "$network_choice" ]; then
    zenity --error --text="No network choice was made."
    exit 1
fi

# Inform the user and enable NTP
zenity --info --text="We are going to setup the timezone first. It is important to be synced in time for the chain to work correctly.\n\nClick OK to enable NTP for timesync." --width=300
if [[ $? -ne 0 ]]; then
    exit 1
fi

sudo timedatectl set-ntp true
zenity --info --text="NTP timesync has been enabled." --width=300

# Loop to attempt timezone setting until confirmed
while true; do
    zenity --info --text="Please choose your CORRECT timezone in the upcoming screen. Press OK to continue." --width=300
    if [[ $? -ne 0 ]]; then
        zenity --error --text="Timezone configuration aborted." --width=300
        exit 1
    fi

    # Launch the timezone configuration GUI
    x-terminal-emulator -e sudo dpkg-reconfigure tzdata 

    # Ask the user if they successfully set the timezone
    if zenity --question --text="Did you successfully set your timezone?" --width=300; then
        zenity --info --text="Timezone set successfully." --width=300
        break
    else
        if zenity --question --text="Timezone setting was not confirmed. Would you like to try setting the timezone again?" --width=300; then
            continue
        else
            zenity --error --text="Timezone setting aborted. Exiting the setup." --width=300
            exit 1
        fi
    fi
done

# Ask the user to choose an Execution Client
execution_client=$(zenity --list --width=500 --height=200 --title="Choose an Execution Client" \
                          --text="Please choose an Execution Client:" \
                          --radiolist --column="Select" --column="Client" \
                          FALSE "Geth (full node, faster sync time)" \
                          FALSE "Erigon (archive node, longer sync time)" \
                          FALSE "Erigon (pruned to keep the last 2000 blocks)")
if [ -z "$execution_client" ]; then
    zenity --error --text="No execution client was chosen. Exiting." --width=300
    exit 1
fi

# Set the chosen client
case "$execution_client" in
    "Geth (full node, faster sync time)")
        ETH_CLIENT="geth"
        ;;
    "Erigon (archive node, longer sync time)"|"Erigon (pruned to keep the last 2000 blocks)")
        ETH_CLIENT="erigon"
        ;;
    *)
        zenity --error --text="Invalid choice. Exiting."
        exit 1
        ;;
esac

# Ask the user to choose a Consensus Client
consensus_client_choice=$(zenity --list --width=300 --height=200 --title="Choose your Consensus Client" \
                                  --text="Select the consensus client for the node setup:" \
                                  --radiolist --column="Select" --column="Client" \
                                  TRUE "Lighthouse" \
                                  --hide-header)

# Check if the user made a choice or cancelled
if [ -z "$consensus_client_choice" ]; then
    zenity --error --text="No consensus client was chosen. Exiting."
    exit 1
fi

# Display choice and set the consensus client variable
CONSENSUS_CLIENT="lighthouse"
zenity --info --text="Lighthouse selected as Consensus Client."

# Enable tab autocompletion for interactive shells (This part may be skipped in GUI)
if [ -n "$BASH_VERSION" ] && [ -n "$PS1" ] && [ -t 0 ]; then
  bind '"\t":menu-complete'
fi

# Get custom path for the blockchain folder
CUSTOM_PATH=$(zenity --entry --title="Installation Path" \
                     --text="Enter the target path for node and client data (Press Enter for default):" \
                     --entry-text "/blockchain")

# Check if the user made a choice or cancelled
if [ -z "$CUSTOM_PATH" ]; then
    CUSTOM_PATH="/blockchain"  # Default path if nothing entered
fi

zenity --info --text="Data will be installed under: $CUSTOM_PATH"

# Define Docker commands
GETH_CMD="sudo -u geth docker run -dt --restart=always \
          --network=host \
          --name execution \
          -v ${CUSTOM_PATH}:/blockchain \
          registry.gitlab.com/pulsechaincom/go-pulse:latest \
          --http \
          --txlookuplimit 0 \
          --gpo.ignoreprice 1 \
          --cache 16384 \
          --metrics \
          --db.engine=leveldb \
          --pprof \
          --http.api eth,net,engine,admin \
          --authrpc.jwtsecret=/blockchain/jwt.hex \
          --datadir=/blockchain/execution/geth"

# Execute Docker command as erigon user

if ! id "erigon" &>/dev/null; then
    sudo useradd -m -s /bin/bash erigon
fi

ERIGON_CMD="sudo -u erigon docker run -dt --restart=always \
          --network=host \
          --name execution_erigon \
          -v ${CUSTOM_PATH}:/blockchain \
          registry.gitlab.com/pulsechaincom/erigon-pulse:latest \
          --chain=${EXECUTION_NETWORK_FLAG} \
          --authrpc.jwtsecret=/blockchain/jwt.hex \
          --datadir=/blockchain/execution/erigon \
          --http \
          --http.api eth,erigon,web3,net,debug,trace,txpool \
          --metrics \
          --pprof \
          --externalcl"

LIGHTHOUSE_CMD="sudo -u lighthouse docker run -dt --restart=always \
                --network=host \
                --name lighthouse \
                -v ${CUSTOM_PATH}:/blockchain \
                registry.gitlab.com/pulsechaincom/lighthouse-pulse:latest \
                lighthouse bn \
                --network mainnet \
                --execution-jwt=/blockchain/jwt.hex \
                --datadir=/blockchain/consensus/lighthouse \
                --execution-endpoint=http://localhost:8551 \
                --checkpoint-sync-url=\"http://checkpoint.node\" \
                --staking \
                --metrics \
                --validator-monitor-auto \
                --http"

# Execute the Docker commands after confirmation
if zenity --question --text="Do you want to execute the Geth Docker command?" --width=500; then
    execute_docker_command "$GETH_CMD"
    zenity --info --text="Geth Docker container started successfully." --width=300
else
    zenity --info --text="Geth Docker container startup aborted." --width=300
fi


if ! eval "$ERIGON_CMD"; then
    zenity --error --text="Failed to start Erigon Docker container."
else
    zenity --info --text="Erigon Docker container started successfully."
fi


if zenity --question --text="Do you want to execute the Lighthouse Docker command?" --width=500; then
    eval $LIGHTHOUSE_CMD
    zenity --info --text="Lighthouse Docker container started successfully." --width=300
else
    zenity --info --text="Lighthouse Docker container startup aborted." --width=300
fi

# Final completion message with Zenity
zenity --info --width=300 --height=100 --text="Congratulations, the node installation/setup is now complete."

