#!/bin/bash

###############################################################################################################
###                                             FUNCTIONS                                                    ##
###############################################################################################################

# --------------------          MESSAGE SYSTEM          -------------------- #
msg() {
    local type="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$timestamp [$type] $message" >> /logs/script.log

    case "$type" in
        success) echo -e "\e[32m$message\e[0m" ;;
        error) echo -e "\e[31m$message\e[0m" ;;
        warning) echo -e "\e[33m$message\e[0m" ;;
        info) echo -e "\e[34m$message\e[0m" ;;
        *) echo "$message" ;;
    esac
}

# --------------------          PRINT MENU          -------------------- #
print_menu() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                          | | | | / _ \                               ║
║                          | |_| |/ /_\ \                              ║
║                          |  _  ||  _  |                              ║
║                          | | | || | | |                              ║
║              _____       \_| |_/\_| |_/   _  _                       ║
║             |_   _|           | |        | || |                      ║
║               | |  _ __   ___ | |_  __ _ | || |  ___  _ __           ║
║               | | | '_ \ / __|| __|/ _` || || | / _ \| '__|          ║
║              _| |_| | | |\__ \| |_| (_| || || ||  __/| |             ║
║              \___/|_| |_||___/ \__|\__,_||_||_| \___||_|             ║
╚══════════════════════════════════════════════════════════════════════╝

EOF
}

# --------------------          STARTUP          -------------------- #
startup() {
    ###   CHECK SUDO
    if [[ $EUID -ne 0 ]]; then
        msg error "Please run this script with sudo or as root."
        exit 1
    fi

    ###  Generate Files
    if [[ ! -d /logs ]]; then
        mkdir -p /logs
    fi

    sudo apt install -y net-tools

    if [[ ! -e "/opt/.net.txt" ]]; then
        config_network
    else
        source /opt/.net.txt
    fi

    ###  UPDATE SYSTEM
    while true; do
        clear
        msg info "Would you like to update the system? (y/n)"
        read -r update_response
        case $update_response in
            y|Y)
                clear
                msg info "Updating system..."
                sudo apt-get update -y
                sudo apt-get upgrade -y
                print_menu
                msg success "System Updated\n"
                break
                ;;
            n|N)
                print_menu
                msg warning "Skipping system update...\n"
                break
                ;;
            *)
                msg error "Invalid input. Please enter y or n."
                ;;
        esac
    done
}

# --------------------          SHUTDOWN          -------------------- #
shutdown() {
    msg info "Cleaning up..."
    sudo apt-get autoclean
    sudo apt-get clean
    sudo apt-get autoremove

    while true; do
        msg info "Would you like to reboot now? (y/n)"
        read -r reboot_response
        case $reboot_response in
            y|Y)
                msg info "Rebooting..."
                sudo reboot
                ;;
            n|N)
                msg info "Exiting without rebooting."
                exit  # Exit both the case and the outer select loop
                ;;
            *)
                msg error "Invalid input. Please enter y or n."
                ;;
        esac
    done
}

# --------------------          CONFIGURE NETWORK          -------------------- #
config_network() {
    clear
    interfaces=$(ip -o link show | awk -F': ' '{print $2}')

    echo "---------- Configure Network Settings ----------"
    echo -e "\nNetwork Info:"
    ip -o addr show

    # Print out the interfaces and prompt the user to select one
    echo -e "\n\nAvailable network interfaces:"
    echo "$interfaces"
    echo -e "\nPlease select an interface: "
    read selected_interface

    # Validate user input
    if ! [[ $interfaces =~ $selected_interface ]]; then
      echo "Invalid selection. Exiting."
      exit 1
    fi

    ip_address=$(ip -o -4 addr list $selected_interface | awk '{print $4}')
    gateway=$(ip route | grep default | grep $selected_interface | awk '{print $3}')
    IFS='.' read -r -a octets <<< "${ip_address%%/*}"  # Remove the /24 and split by '.'
    subnet="${octets[0]}.${octets[1]}.${octets[2]}.0/24"

    # Write the details to a file
    echo "Interface: $selected_interface"
    echo "IP Address: $ip_address"
    echo "Gateway: $gateway"
    echo "Subnet: $subnet"

    new_ip="0.0.0.0"
    while [[ $new_ip == "0.0.0.0" ]]; do
      # Prompt the user for a new IP address
      echo -e "\nWe will set a static IP for this system to make it easier to access."
      echo -e "Please enter a new IP address (e.g., $ip_address): "
      read new_ip

      if ! [[ $new_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$ ]]; then
          echo "Invalid IP address format. Please try again."
          new_ip="0.0.0.0"
      fi
    done


    # Create a Netplan configuration file
    cat <<EOL | sudo tee /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      dhcp4: no
      addresses:
        - $new_ip
      gateway4: $gateway
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOL

    # Apply the new network configuration
    sudo netplan apply

    # Verify the new settings
    echo -e "\nNew Network Configuration:"

    while true; do
        clear
        msg info "Do you have an external domain? (y/n)"
        read -r domain_response
        case $domain_response in
            y|Y)
                echo -e "Please enter your domain (e.g., example.com): "
                read domain
                break
                ;;
            n|N)
                domain = "example.com"
                break
                ;;
            *)
                msg error "Invalid input. Please enter y or n."
                ;;
        esac
    done

    new_ip=${new_ip%%/*}   ## Remove subnet ID from IP

    # Write the details to a file
    echo "selected_interface=$selected_interface" > /opt/.net.txt
    echo "new_ip=$new_ip" >> /opt/.net.txt
    echo "gateway=$gateway" >> /opt/.net.txt
    echo "subnet=$subnet" >> /opt/.net.txt
    echo "domain=$domain" >> /opt/.net.txt
}


###############################################################################################################
###                                             INSTALLERS                                                   ##
###############################################################################################################

# --------------------          HOME ASSISTANT INSTALL          -------------------- #
install_homeassistant() {
    check_docker
    clear

    msg info "Installing Home Assistant..."
    if ! grep -q "homeassistant:" /opt/docker-compose.yaml; then
        # Entry does not exist, add it
        cat <<EOL >> /opt/docker-compose.yaml
  homeassistant:
    container_name: homeassistant
    image: "homeassistant/home-assistant"
    volumes:
      - /opt/homeassistant/config:/config
      - /home/homeassistant/Videos:/media
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    ports:
      - "8123:8123"
    restart: always
    privileged: true
    networks:
      - homenet
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.homeassistantlocal.loadbalancer.server.port: 8123
      traefik.http.routers.homeassistantlocal.service: homeassistantlocal
      traefik.http.routers.homeassistantlocal.entrypoints: web, websecure
      traefik.http.routers.homeassistantlocal.tls: true
      traefik.http.routers.homeassistantlocal.rule: Host(\`home.local\`)
      ## External
      traefik.http.services.homeassistantweb.loadbalancer.server.port: 8123
      traefik.http.routers.homeassistantweb.service: homeassistantweb
      traefik.http.routers.homeassistantweb.entrypoints: web, websecure
      traefik.http.routers.homeassistantweb.rule: Host(\`home.$domain\`)
      traefik.http.routers.homeassistantweb.tls: true
      traefik.http.routers.homeassistantweb.tls.certresolver: production

EOL
        msg success "Home Assistant configuration added to docker-compose.yaml"
    else
        msg warning "Home Assistant entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
     
    if docker ps | grep -q "homeassistant"; then
        print_menu
        msg success "Home Assistant successfully installed and running"

	    ping -c 1 -W 1 home.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://home.local"
        else
            msg info "Local Network - http://$new_ip:8123"
        fi
        msg info "This PC - http://127.0.0.1:8123\n"
    else
        print_menu
        msg error "Home Assistant container failed to start\n"
    fi
}

# --------------------          NODE RED INSTALL          -------------------- #
install_nodered() {
    check_docker
    clear

    msg info "Installing Node-RED..."
    if ! grep -q "nodered:" /opt/docker-compose.yaml; then
        # Entry does not exist, add it
        cat <<EOL >> /opt/docker-compose.yaml
  nodered:
    container_name: nodered
    image: "nodered/node-red"
    volumes:
      - /opt/node-red/config:/data
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    ports:
      - "1880:1880"
    user: 1000:1000
    restart: always
    networks:
      - homenet
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.noderedlocal.loadbalancer.server.port: 1880
      traefik.http.routers.noderedlocal.service: noderedlocal
      traefik.http.routers.noderedlocal.entrypoints: web, websecure
      traefik.http.routers.noderedlocal.tls: true
      traefik.http.routers.noderedlocal.rule: Host(\`nodered.local\`)
      ## External
      traefik.http.services.noderedweb.loadbalancer.server.port: 1880
      traefik.http.routers.noderedweb.service: noderedweb
      traefik.http.routers.noderedweb.entrypoints: web, websecure
      traefik.http.routers.noderedweb.rule: Host(\`nodered.$domain\`)
      traefik.http.routers.noderedweb.tls: true
      traefik.http.routers.noderedweb.tls.certresolver: production

EOL
        msg success "Node-RED configuration added to docker-compose.yaml"
    else
        msg warning "Node-RED entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    		
    # Set same user as Node Red to allow permissions on shared volume.
    sudo chown -R 1000:1000 /opt/node-red/config
    
    if docker ps | grep -q "nodered"; then
        prep_nodered
        print_menu
        msg success "Node-RED successfully installed and running"

	    ping -c 1 -W 1 nodered.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://nodered.local"
        else
            msg info "Local Network - http://$new_ip:1880"
        fi
        msg info "This PC - http://127.0.0.1:1880\n"
    else
        print_menu
        msg error "Node-RED container failed to start\n"
    fi
}

prep_nodered(){
     docker exec -it nodered npm install node-red-contrib-home-assistant-websocket
     docker restart nodered
}

# --------------------          MOSQUITTO INSTALL          -------------------- #
install_mosquitto() {
    check_docker
    clear

    msg info "Installing Mosquitto MQTT..."
    if ! grep -q "mosquitto:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  mosquitto:
    container_name: mosquitto
    image: "eclipse-mosquitto"
    restart: always
    ports:
        - "1883:1883"
        - "9001:9001"
    volumes:
        - /opt/mosquitto:/mosquitto
    networks:
        - homenet

EOL
        msg success "Mosquitto configuration added to docker-compose.yaml"
    else
        msg warning "Mosquitto entry already exists in docker-compose.yaml"
    fi

    if [[ ! -s /opt/mosquitto/config/mosquitto.conf ]]; then
      sudo mkdir -p /opt/mosquitto
      sudo mkdir -p /opt/mosquitto/config
      sudo touch /opt/mosquitto/config/mosquitto.conf
    
        cat << EOL >> /opt/mosquitto/config/mosquitto.conf
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
listener 1883

## Authentication ##
allow_anonymous true
EOL
    else
        msg info "Configuration file already exists, skipping..."
    fi
    
    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    
    if docker ps | grep -q "mosquitto"; then
        print_menu
        msg success "Mosquitto successfully installed and running"
    else
        print_menu
        msg error "Mosquitto container failed to start\n"
    fi
}

# --------------------          KUMA UPTIME INSTALL          -------------------- #
install_kuma() {
    check_docker
    clear

    msg info "Installing Kuma Uptime..."
    if ! grep -q "kuma:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  kuma:
    image: louislam/uptime-kuma
    container_name: kuma
    volumes:
      - /opt/kuma:/app/data
    ports:
      - "3001:3001"
    networks:
      - homenet
    restart: always
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.kumalocal.loadbalancer.server.port: 3001
      traefik.http.routers.kumalocal.service: kumalocal
      traefik.http.routers.kumalocal.entrypoints: web, websecure
      traefik.http.routers.kumalocal.tls: true
      traefik.http.routers.kumalocal.rule: Host(\`kuma.local\`)
      ## External
      traefik.http.services.kumaweb.loadbalancer.server.port: 3001
      traefik.http.routers.kumaweb.service: kumaweb
      traefik.http.routers.kumaweb.entrypoints: web, websecure
      traefik.http.routers.kumaweb.rule: Host(\`kuma.$domain\`)
      traefik.http.routers.kumaweb.tls: true
      traefik.http.routers.kumaweb.tls.certresolver: production

EOL
        msg success "Kuma configuration added to docker-compose.yaml"
    else
        msg warning "Kuma entry already exists in docker-compose.yaml"
    fi
    
    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    
    if docker ps | grep -q "kuma"; then
        print_menu
        msg success "Kuma successfully installed and running"

	    ping -c 1 -W 1 kuma.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://kuma.local"
        else
            msg info "Local Network - http://$new_ip:3001"
        fi
        msg info "This PC - http://127.0.0.1:3001\n"
    else
        print_menu
        msg error "Kuma container failed to start\n"
    fi
}

# --------------------          LOGITCH MEDIA SERVER INSTALL          -------------------- #
install_lms() {
    check_docker
    clear

    msg info "Installing Logitech Media Server..."
    if ! grep -q "lms:" /opt/docker-compose.yaml; then
        # Entry does not exist, add it
        cat <<EOL >> /opt/docker-compose.yaml
  lms:
    container_name: lms
    image: lmscommunity/logitechmediaserver
    volumes:
      - /opt/lms/config:/config
      - /home/$(whoami)/Music:/music:ro
      - /home/$(whoami)/Music/playlists:/playlist
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
  #  devices:
  #    - /dev/snd    # For Adding USB Sound Card for Line-In Audio Input
    ports:
      - 9000:9000/tcp
      - 9090:9090/tcp
      - 3483:3483/tcp
      - 3483:3483/udp
    restart: unless-stopped
    networks:
      - homenet
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.lmslocal.loadbalancer.server.port: 9000
      traefik.http.routers.lmslocal.service: lmslocal
      traefik.http.routers.lmslocal.entrypoints: web, websecure
      traefik.http.routers.lmslocal.tls: true
      traefik.http.routers.lmslocal.rule: Host(\`music.local\`)
      ## External
      traefik.http.services.lmsweb.loadbalancer.server.port: 9000
      traefik.http.routers.lmsweb.service: lmsweb
      traefik.http.routers.lmsweb.entrypoints: web, websecure
      traefik.http.routers.lmsweb.rule: Host(\`music.$domain\`)
      traefik.http.routers.lmsweb.tls: true
      traefik.http.routers.lmsweb.tls.certresolver: production

EOL
        msg success "Logitech Media Server configuration added to docker-compose.yaml"
    else
        msg warning "Logitech Media Server entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
     
    if docker ps | grep -q "logitechmediaserver"; then
        print_menu
        msg success "Logitech Media Server successfully installed and running"

	    ping -c 1 -W 1 music.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://music.local"
        else
            msg info "Local Network - http://$new_ip:9000"
        fi
        msg info "This PC - http://127.0.0.1:9000\n"
    else
        print_menu
        msg error "Logitech Media Server container failed to start\n"
    fi
}

# --------------------          FIRGATE INSTALL          -------------------- #
install_frigate() {
    check_docker
    clear

    msg info "Installing Frigate NVR..."
    if ! grep -q "frigate:" /opt/docker-compose.yaml; then
        # Entry does not exist, add it
        cat <<EOL >> /opt/docker-compose.yaml
  frigate:
    container_name: frigate
    image: ghcr.io/blakeblackshear/frigate:stable
    shm_size: "64mb" # NEEDS TO BE UPDATED BASED ON CAMERAS - Each Camera = (<width> * <height> * 1.5 * 9 + 270480) / 1048576)
#    devices:
#      - /dev/bus/usb:/dev/bus/usb # Passes the USB Coral, NEEDS TO BE UPDATED FOR USER HARDWARE
#      - /dev/apex_0:/dev/apex_0 # Passes a PCIe Coral Driver Instructions: https://coral.ai/docs/m2/get-started/#2a-on-linux
#      - /dev/dri/renderD128 # Intel hwaccel, NEEDS TO BE UPDATED FOR USER HARDWARE
    volumes:
      - /opt/frigate/config:/config
      - /home/frigate/Videos:/media/frigate
      - type: tmpfs # Optional: Uses 1GB of RAM, reduces SSD/SD Card wear
        target: /tmp/cache
        tmpfs:
          size: 1000000000
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    ports:
      - "5000:5000"
      - "8554:8554" # RTSP Feeds
      - "8555:8555/tcp" # WebRTC over TCP
      - "8555:8555/udp" # WebRTC over UDP
    environment:
      FRIGATE_RTSP_PASSWORD: "password"
    privileged: true
    restart: unless-stopped
    networks:
      - homenet
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.frigatelocal.loadbalancer.server.port: 5000
      traefik.http.routers.frigatelocal.service: frigatelocal
      traefik.http.routers.frigatelocal.entrypoints: web, websecure
      traefik.http.routers.frigatelocal.tls: true
      traefik.http.routers.frigatelocal.rule: Host(\`nvr.local\`)
      ## External
      traefik.http.services.frigateweb.loadbalancer.server.port: 5000
      traefik.http.routers.frigateweb.service: frigateweb
      traefik.http.routers.frigateweb.entrypoints: web, websecure
      traefik.http.routers.frigateweb.rule: Host(\`nvr.$domain\`)
      traefik.http.routers.frigateweb.tls: true
      traefik.http.routers.frigateweb.tls.certresolver: production

EOL
        msg success "Frigate NVR configuration added to docker-compose.yaml"
    else
        msg warning "Frigate NVR entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    
    if docker ps | grep -q "frigate"; then
        print_menu
        msg success "Frigate NVR successfully installed and running"

	    ping -c 1 -W 1 nvr.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://nvr.local"
        else
            msg info "Local Network - http://$new_ip:5000"
        fi
        msg info "This PC - http://127.0.0.1:5000\n"
    else
        print_menu
        msg error "Frigate NVR container failed to start\n"
    fi
}

# --------------------          CLOUDFLARED INSTALL          -------------------- #
install_cloudflared() {
    clear
    msg info "Installing Cloudflared..."
                
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

    sudo apt-get update && sudo apt-get install cloudflared

    clear
    msg success "Cloudflared downloaded successfully\n"

    # Get the home directory of the user who invoked sudo
    USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)

    # Execute cloudflared login as the original user
    sudo -u $SUDO_USER bash -c "cloudflared login"

    clear
    msg success "Login Successful\n"
        
    # Prompt for Tunnel Name
    while [[ -z $TUNNEL_NAME ]]; do
        msg info "Enter the tunnel name: "
        read TUNNEL_NAME
    done

    # Create a tunnel and capture the Tunnel UUID
    TUNNEL_UUID=$(sudo -u $SUDO_USER bash -c "cloudflared tunnel create $TUNNEL_NAME" | awk '/Created tunnel/{print $NF}')

    # Check if Tunnel UUID was captured
    if [[ -z $TUNNEL_UUID ]]; then
        msg error "Failed to obtain Tunnel UUID. Exiting."
        exit 1
    fi

    # Create & Route Sub Domain
    sudo -u $SUDO_USER bash -c "cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_NAME"

    # Define the path to the credentials file using the Tunnel UUID
    CREDENTIALS_FILE_PATH="$USER_HOME/.cloudflared/$TUNNEL_UUID.json"

    # Create the config.yml file with the necessary parameters as the original user
    sudo -u $SUDO_USER bash -c "cat <<EOL > $USER_HOME/.cloudflared/config.yml
url: localhost:80
tunnel: $TUNNEL_UUID
credentials-file: $CREDENTIALS_FILE_PATH
EOL"

    clear
        
    sudo -u $SUDO_USER bash -c "cloudflared tunnel --config $USER_HOME/.cloudflared/config.yml run" > /dev/null 2>&1 &
        
    if sudo -u $SUDO_USER crontab -l | grep -q "cloudflared tunnel"; then
        msg info "Command is already in crontab"
    else
        # Add the command to crontab to run it at reboot for the original user
        sudo -u $SUDO_USER bash -c "(crontab -l 2>/dev/null; echo \"@reboot cloudflared tunnel --config $USER_HOME/.cloudflared/config.yml run\") | crontab -"
        msg success "Cloudflare added to startup"
    fi
        
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        print_menu
        msg success "Cloudflared successfully installed and running\n"
    else
        print_menu
        msg error "Cloudflared container failed to start\n"
    fi
}

# --------------------          APACHE INSTALL          -------------------- #
install_apache() {
    check_docker
    clear
    msg info "Installing Apache Web Server..."
    if ! grep -q "apache:" /opt/docker-compose.yaml; then
        # Entry does not exist, add it
        cat <<EOL >> /opt/docker-compose.yaml
  apache:
    image: httpd:latest
    container_name: apache
    ports:
      - '880:880'
    volumes:
      - /opt/apache/website:/usr/local/apache2/htdocs
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    networks:
      - homenet
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.apachelocal.loadbalancer.server.port: 80
      traefik.http.routers.apachelocal.service: apachelocal
      traefik.http.routers.apachelocal.entrypoints: web, websecure
      traefik.http.routers.apachelocal.tls: true
      traefik.http.routers.apachelocal.rule: Host(\`web.local\`)
      ## External
      traefik.http.services.apacheweb.loadbalancer.server.port: 80
      traefik.http.routers.apacheweb.service: apacheweb
      traefik.http.routers.apacheweb.entrypoints: web, websecure
      traefik.http.routers.apacheweb.rule: Host(\`web.$domain\`)
      traefik.http.routers.apacheweb.tls: true
      traefik.http.routers.apacheweb.tls.certresolver: production
EOL
        msg success "Apache configuration added to docker-compose.yaml"
    else
        msg warning "Apache entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    
    if docker ps | grep -q "apache"; then
        print_menu
        msg success "Apache Web Server successfully installed and running"

	    ping -c 1 -W 1 web.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://web.local"
        else
            msg info "Local Network - http://$new_ip:880"
        fi
        msg info "This PC - http://127.0.0.1:880\n"
    else
        print_menu
	    msg error "Apache Web Server failed to start\n"
	fi
}

# --------------------          DUCKDNS INSTALL          -------------------- #
install_duckdns() {
    check_docker
    clear

    msg info "Installing DuckDNS..."
    if ! grep -q "duckdns:" /opt/docker-compose.yaml; then
        echo "http://duckdns.org"
	    # Prompt the user to enter a name for the device
	    msg info "Enter Subdomain: (_____.duckdns.com)"
	    read -r subdomain

 	    # Prompt the user to enter a name for the device
	    msg info "Enter Token: "
	    read -r token
    
        cat << EOL >> /opt/docker-compose.yaml
  duckdns:
    container_name: duckdns
    image: "linuxserver/duckdns"
    environment:
      - PUID=999
      - PGID=999
      - SUBDOMAINS=$subdomain
      - TOKEN=$token
    volumes:
      - /opt/duckdns:/config
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    restart: unless-stopped
    networks:
        - homenet

EOL
        msg success "DuckDNS configuration added to docker-compose.yaml"
    else
        msg warning "DuckDNS entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans

    if docker ps | grep -q "duckdns"; then
        print_menu
        msg success "DuckDNS successfully installed and running\n"
    else
        print_menu
        msg error "DuckDNS container failed to start\n"
    fi
}

# --------------------          WIREGUARD INSTALL          -------------------- #
install_wireguard() {
    check_docker
    clear

    msg info "Installing WireGuard..."
    if ! grep -q "wireguard:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  wireguard:
    container_name: wireguard
    image: "linuxserver/wireguard"
    cap_add:
        - NET_ADMIN
        - SYS_MODULE
    environment:
        - PUID=998
        - PGID=998
    volumes:
        - /opt/wireguard:/config
        - /lib/modules:/lib/modules:ro
	- /etc/localtime:/etc/localtime:ro
        - /etc/timezone:/etc/timezone:ro
    ports:
        - "51820:51820/udp"
    sysctls:
        - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
    networks:
        - homenet

EOL
        msg success "WireGuard configuration added to docker-compose.yaml"
    else
        msg warning "WireGuard entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans

    if docker ps | grep -q "wireguard"; then
        print_menu
        msg success "WireGuard successfully installed and running\n"
    else
        print_menu
        msg error "WireGuard container failed to start\n"
    fi
}

# --------------------          TRAEFIK INSTALL          -------------------- #
install_traefik() {
    check_docker
    clear

    msg info "Installing Traefik..."
    ###   Set Config File

    # Prompt the user to enter a name for the device
    msg info "\nEnter E-mail for SSL Certificates: "
    read -r email
    
    if [[ ! -s /opt/traefik/traefik.yaml ]]; then
        sudo mkdir -p /opt/traefik
	sudo touch /opt/traefik/traefik.yaml
    
        cat << EOL >> /opt/traefik/traefik.yaml
## General
global:
  checkNewVersion: false
  sendAnonymousUsage: false

## Dashboard  (Don't enable in production)
# api: 
#   dashboard: true
#   insecure: true

## Ports
entryPoints:
  web:
    address: :80
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: :443

## SSL Certs
certificatesResolvers:
  production:
    acme:
      email: $email
      storage: /etc/traefik/certs/acme.json
      caServer: "https://acme-v02.api.letsencrypt.org/directory"
      httpChallenge:
        entryPoint: web

## TLS Stores
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/certs/certificate.crt
        keyFile: /etc/traefik/certs/private.key

## Docker Setup
providers:
  docker:
    # -- (Optional) Enable this, if you want to expose all containers automatically
    exposedByDefault: false
EOL
    else
        msg info "Configuration file already exists, skipping..."
    fi
    
    ###   Install Container
    if ! grep -q "traefik:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  traefik:
    container_name: traefik
    image: "traefik"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"   # Dashboard (Disable in Production)
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/traefik:/etc/traefik
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    networks:
      - homenet
      
EOL
        msg success "Traefik configuration added to docker-compose.yaml"
    else
        msg warning "Traefik entry already exists in docker-compose.yaml"
    fi
    docker-compose -f /opt/docker-compose.yaml up -d

    docker exec traefik mkdir -p /etc/traefik/
    docker exec traefik mkdir -p /etc/traefik/certs
    docker exec traefik touch /etc/traefik/certs/acme.json
    docker exec traefik chmod 600 -R /etc/traefik/certs

    #  Create Local SSL cert
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /opt/traefik/certs/private.key -out /opt/traefik/certs/certificate.crt -subj "/O=Local Network/CN=*.local/emailAddress=$email" -addext "subjectAltName=DNS:*.local"

    # Auto Regenerate Every 6 Months
    (crontab -l; echo "0 3 1 1,7 * /usr/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /opt/traefik/certs/private.key -out /opt/traefik/certs/certificate.crt -subj \"/O=Local Network/CN=*.local/emailAddress=$email\" -addext \"subjectAltName=DNS:*.local\"") | crontab -

    docker restart traefik
   
    if docker ps | grep -q "traefik"; then
        print_menu
        msg success "Traefik successfully installed and running"

	    ping -c 1 -W 1 traefik.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://traefik.local"
        else
            msg info "Local Network - http://$new_ip:8080"
        fi
        msg info "This PC - http://127.0.0.1:8080\n"
        msg info "NOTE: You must enable access in the traefik.yaml\n"
    else
        print_menu
        msg error "Traefik container failed to start\n"
    fi
}


# --------------------          PI HOLE INSTALL          -------------------- #
install_pihole() {
    check_docker
    clear

    # Split the IP address into octets, and increment the last octet
    IFS='.' read -r -a octets <<< "${new_ip%%/*}"  # Remove the /24 and split by '.'
    last_octet=$(( ${octets[3]} + 1 ))  # Increment the last octet
    new_ip_incremented="${octets[0]}.${octets[1]}.${octets[2]}.$last_octet"  # Reassemble the IP

    msg info "Installing Pi Hole..."
    if ! grep -q "pihole:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    networks:
      aworldnet:
        ipv4_address: $new_ip_incremented    ## Static IP +1
      homenet:
    volumes:
      - /opt/pihole:/etc/pihole
      - /opt/pihole//dnsmasq.d:/etc/dnsmasq.d
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    restart: unless-stopped
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.piholelocal.loadbalancer.server.port: 80
      traefik.http.routers.piholelocal.service: piholelocal
      traefik.http.routers.piholelocal.entrypoints: web, websecure
      traefik.http.routers.piholelocal.rule: Host(\`adblock.local\`)
      traefik.http.routers.piholelocal.tls: true
      ## External
      traefik.http.services.piholeweb.loadbalancer.server.port: 80
      traefik.http.routers.piholeweb.service: piholeweb
      traefik.http.routers.piholeweb.entrypoints: web, websecure
      traefik.http.routers.piholeweb.rule: Host(\`adblock.$domain\`)
      traefik.http.routers.piholeweb.tls: true
      traefik.http.routers.piholeweb.tls.certresolver: production

EOL
        msg success "Pi Hole configuration added to docker-compose.yaml"
    else
        msg warning "Pi Hole entry already exists in docker-compose.yaml"
    fi

    ###   Set Config File
    if [[ ! -s /opt/pihole/custom.list ]]; then
        mkdir /opt/pihole
	    sudo touch /opt/pihole/custom.list
        cat << EOL >> /opt/pihole/custom.list
### Server DNS Rewrites
$new_ip          adblock.local
$new_ip          traefik.local
$new_ip          docker.local
$new_ip          home.local
$new_ip          nvr.local
$new_ip          music.local
$new_ip          web.local
$new_ip          nodered.local
$new_ip          kuma.local
EOL
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans

    docker exec -it pihole /usr/local/bin/pihole -a -p  # Set password for system
    
    if docker ps | grep -q "pihole"; then
        print_menu
        msg success "Pi Hole successfully installed and running"

	    ping -c 1 -W 1 adblock.local > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
            msg info "Local Network - http://adblock.local"
        else
            msg info "Local Network - http://$new_ip_incremented:80"
        fi
    else
        print_menu
        msg error "Pi Hole container failed to start\n"
    fi
}

# --------------------          NUT INSTALL          -------------------- #
install_NUT() {
    clear
    
    msg info "Installing Nut..."
    sudo apt-get install -y nut nut-client nut-server &>> \logs\nut-error.log || {
        msg error "INSTALLATION FAILED! Check Log for Details."
        return
    }

	# Configuring files
    CONFIG_DIR="/etc/nut"
    for file in ups.conf upsmon.conf upsd.conf nut.conf upsd.users; do
        if [[ -e "$CONFIG_DIR/$file" ]]; then
            sudo rm "$CONFIG_DIR/$file"
        fi
        touch "$CONFIG_DIR/$file"
    done
                
    msg success "NUT Successfully Installed."
                
    sleep 1
    clear

    # Configure Files
    echo -e "maxretry = 3\npollinterval = 1\n" | sudo tee "$CONFIG_DIR/ups.conf"
    echo -e "RUN_AS_USER root\n" | sudo tee "$CONFIG_DIR/upsmon.conf"
    echo "LISTEN 127.0.0.1 3493" | sudo tee "$CONFIG_DIR/upsd.conf"
    echo "MODE=standalone" | sudo tee "$CONFIG_DIR/nut.conf"
    echo -e "[monuser]\npassword = secret\nadmin master" | sudo tee "$CONFIG_DIR/upsd.users"
                
	# Get the output of the nut-scanner command and save to a temporary file
	sudo nut-scanner -U | grep -A 9 '^\[nutdev' > /tmp/ups_data.txt &

	# Read the data from the temporary file
	ups_data=$(cat /tmp/ups_data.txt)

	# Initialize an empty upsmon.conf content string
	upsmon_conf_content=""

	# Input file name
	input_file="/tmp/ups_data.txt"

	# Use csplit to split the input file into separate section files for each nutdev
	csplit -z -f section "$input_file" '/^\[nutdev/' '{*}'

	# Iterate over each section file
	for section_file in section*; do
		# Get the values of specified variables from the section file
		driver=$(grep -oP '(?<=driver = ").*(?=")' "$section_file" | sed 's/^\t//')
		port=$(grep -oP '(?<=port = ").*(?=")' "$section_file" | sed 's/^\t//')
		vendorid=$(grep -oP '(?<=vendorid = ").*(?=")' "$section_file" | sed 's/^\t//')
		productid=$(grep -oP '(?<=productid = ").*(?=")' "$section_file" | sed 's/^\t//')
		product=$(grep -oP '(?<=product = ").*(?=")' "$section_file" | sed 's/^\t//')
		serial=$(grep -oP '(?<=serial = ").*(?=")' "$section_file" | sed 's/^\t//')

		# Prompt the user to enter a name for the device
		msg info -n "Enter a name for the device with Serial Number: $serial: "
		read -r name

		# Append the information to ups.conf
		ups_conf_content="[$name]
		driver = \"$driver\"
		port = \"$port\"
		vendorid = \"$vendorid\"
		productid = \"$productid\"
		serial = \"$serial\"
		"
		echo -e "$ups_conf_content" | sudo tee -a "$CONFIG_DIR/ups.conf"

		# Append the monitor information to upsmon.conf
		echo "MONITOR $name@localhost 1 admin password master" | sudo tee -a "$CONFIG_DIR/upsmon.conf"

	    # Remove the section file
		rm "$section_file"
	done

    # Restart Services
    for service in nut-server nut-client nut-monitor; do
        sudo service $service restart
    done

    sudo upsdrvctl stop
    sudo upsdrvctl start
    		

    print_menu
    msg success "NUT Server successfully installed and running\n"
}

# --------------------          FTP INSTALL          -------------------- #
install_FTP() {
    clear

    msg info "Configuring FTP..."        
    apt-get install -y vsftpd

    rm /etc/vsftpd.conf            
    touch /etc/vsftpd.conf
    msg success "FTP Successfully Configured."     

    sleep 1
    clear
       
    mkdir /etc/ssl/private
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/vsftpd.pem -out /etc/ssl/private/vsftpd.pem

    # Configure vsftpd.conf
    cat <<EOL >> /etc/vsftpd.conf
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES

rsa_cert_file=/etc/ssl/private/vsftpd.pem
rsa_private_key_file=/etc/ssl/private/vsftpd.pem
EOL

    sudo systemctl restart vsftpd
    clear
    		
    if docker ps | grep -q "apache"; then
        print_menu
        msg success "FTP Server successfully configured\n"
	else
        print_menu
        msg error "FTP Server failed to start\n"
    fi
}

# --------------------          DOCKER INSTALL          -------------------- #
install_docker() {
    clear

    msg info "Installing Docker Compose..."

    # Docker and docker compose prerequisites
    sudo apt-get install -y curl gnupg ca-certificates lsb-release apt-transport-https

    # Add Docker’s official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Set up the Docker stable repository
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update the package database with the Docker packages from the newly added repo
    sudo apt-get update -y

    # Install Docker CE
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io || {
        msg error "Failed to install Docker packages"
    }

    # Allow current user to run Docker commands without sudo
    sudo usermod -aG docker $(whoami)

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Create Docker Compose File
    if [[ ! -f /opt/docker-compose.yaml ]]; then
	    touch /opt/docker-compose.yaml
        cat <<EOL >> /opt/docker-compose.yaml  # Start of here-document
version: '3.9'

networks:
  homenet:
    driver: bridge
  aworldnet:
    driver: macvlan
    driver_opts:
      parent: $selected_interface
    ipam:
      config:
        - subnet: $subnet
          gateway: $gateway

services:

EOL
    fi

    # Output versions
    clear

    docker --version
    docker-compose --version

    # The script is finished
    msg success "\nDocker and Docker Compose installed successfully!\n"

    install_portainer
}

# --------------------          PORTAINER INSTALL          -------------------- #
install_portainer() {
    check_docker
    clear

    msg info "Installing Portainer..."
    if ! grep -q "portainer:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  portainer:
    image: portainer/portainer-ce:latest
    networks:
      - homenet
    ports:
      - 9443:9443
    volumes:
      - /opt/portainer/data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
    labels:
      traefik.enable: true
      traefik.docker.network: "opt_homenet"
      ## Internal
      traefik.http.services.portainerlocal.loadbalancer.server.port: 9443
      traefik.http.routers.portainerlocal.service: portainerlocal
      traefik.http.routers.portainerlocal.entrypoints: web, websecure
      traefik.http.routers.portainerlocal.rule: Host(\`docker.local\`)
      traefik.http.routers.portainerlocal.tls: true
      ## External
      traefik.http.services.portainerweb.loadbalancer.server.port: 9443
      traefik.http.routers.portainerweb.service: portainerweb
      traefik.http.routers.portainerweb.entrypoints: web, websecure
      traefik.http.routers.portainerweb.rule: Host(\`docker.$domain\`)
      traefik.http.routers.portainerweb.tls: true
      traefik.http.routers.portainerweb.tls.certresolver: production

EOL
        msg success "Portainer configuration added to docker-compose.yaml"
    else
        msg warning "Portainer entry already exists in docker-compose.yaml"
    fi
    
    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans

    grep "docker.local" /etc/hosts
    
    if docker ps | grep -q "portainer"; then
        print_menu
        msg success "Portainer successfully installed and running\n"
    else
        print_menu
        msg error "Portainer container failed to start\n"
    fi
}

# --------------------          FULL INSTALL          -------------------- #
additional_applications() {
    PS3='Select additional applications to install: '
    additional_options=("Cloudflared" "Apache Web Server" "Frigate NVR" "Logitech Media Server" "NUT UPS Tool" "Done")
    selected_apps=()
    
    while true; do
        clear
        msg info "The following optional applications have been selected for install:\n"

        for app in "${selected_apps[@]}"; do
            echo "- $app"
        done
	
	echo ""
	
        select additional_opt in "${additional_options[@]}"; do
            case $REPLY in
                [1-6])
	            # Initialize a flag to false
        	    already_selected=false
        	    # Index variable to keep track of the position of the app in selected_apps
        	    index_to_remove=-1 

        	    # Check if the selected application is already in the selected_apps array
        	    for index in "${!selected_apps[@]}"; do
            		if [[ "${selected_apps[index]}" == "$additional_opt" ]]; then
                	    already_selected=true
                	    index_to_remove=$index  # Update index_to_remove with the current index
                	    break
            	        fi
        	    done

	            # If the application wasn't already selected, add it to the selected_apps array
        	    if [[ "$already_selected" == false ]]; then
	                selected_apps+=("$additional_opt")
	            else
	                # If the app was already selected, remove it from the selected_apps array
	                unset "selected_apps[$index_to_remove]"
	            fi
	            break
                    ;;
                7)
                    return
                    ;;
                *)
                    msg warning "Invalid option $REPLY"
                    ;;
            esac
            REPLY=
        done
    done
}

confirm_installation() {
    clear
    msg info "The following applications will be installed:"

    for app in "${apps_to_install[@]}"; do
        echo "- $app"
    done

    while true; do
    	echo ""
        msg info "Do you wish to proceed with the installation? (y/n)"
        read -r confirm_response
        case $confirm_response in
            y|Y)
                return 0  # Return with success to proceed
                ;;
            n|N)
                msg info "Installation cancelled by user."
                clear
                print_menu
                return 1  # Return with failure to cancel
                ;;
            *)
                msg error "Invalid input. Please enter y or n."
                ;;
        esac
    done
}

install_full() {
    clear
    cat << EOF
The following recommended applications will automatically be installed:

1. Docker
2. Home Assistant
3. Node Red
4. FTP

EOF
    # Set Reccommended Starting Apps
    apps_to_install=("Docker" "Home Assistant" "Node Red" "FTP")

    while true; do
        msg info "Would you like to install any other optional applications? (y/n)"
        read -r other_apps_response
        case $other_apps_response in
            y|Y)
                additional_applications
                break  # Exit the loop on valid input
                ;;
            n|N)
                msg info "Proceeding with the installation of the listed applications..."
                break  # Exit the loop on valid input
                ;;
            *)
                msg error "Invalid input. Please enter y or n."
                ;;
        esac
    done

    for app in "${selected_apps[@]}"; do
        apps_to_install+=("$app")
    done

    confirm_installation || return  # Confirm with the user before proceeding

    ###   ACTUAL INSTALLATION
    install_docker
    install_homeassistant
    install_nodered
    install_FTP

    for app in "${selected_apps[@]}"; do
        case $app in
            "Cloudflared")
                install_cloudflared
                ;;
            "Apache Web Server")
                install_apache
                ;;
            "Frigate NVR")
                install_frigate
                ;;
            "Logitech Media Server")
                install_lms
                ;;
            "NUT UPS Tool")
                install_NUT
                ;;
            *)
                msg warning "Unknown application: $app"
                ;;
        esac
    done
}


###############################################################################################################
###                                          INSTALL CHECKS                                                  ##
###############################################################################################################

# --------------------          HOME ASSISTANT CHECK          -------------------- #
check_homeassistant() {
    if ! docker ps | grep -q "home-assistant"
    then
        msg info "Home Assistant is required to run this script."
        while true; do
            read -p "Would you like to install Home Assistant now? (y/n): " yn
            case $yn in
                [Yy]* )
                    install_homeassistant
                    break;;
                [Nn]* )
                    msg error "Exiting as Home Assistant is not installed."
                    exit 1;;
                * )
                    msg warning "Please answer yes or no.";;
            esac
        done
    fi
}

# --------------------          DOCKER CHECK          -------------------- #
check_docker() {
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null
    then
        msg info "\nDocker is required to run this script."
        while true; do
            read -p "Would you like to install Docker now? (y/n): " yn
            case $yn in
                [Yy]* )
                    install_docker
                    break;;
                [Nn]* )
                    msg error "Exiting as Docker is not installed."
                    exit 1;;
                * )
                    msg warning "Please answer yes or no.";;
            esac
        done
    fi
}


###############################################################################################################
###                                             SUB-MENUS                                                    ##
###############################################################################################################

# --------------------          AUTOMATION          -------------------- #
install_automation() {
    PS3='Select Application for Download: '
    automation_options=("Home Assistant" "Node Red" "Mosquitto" "Kuma Uptime" "Back")
    select automation_opt in "${automation_options[@]}"
    do
        case $REPLY in     
	        1) ###   HOME ASSISTANT
                install_homeassistant
    		    ;;
            2) ###   NODE RED
                install_nodered
    		    ;;
	    3) ###   MOSQUITTO MQTT
                install_mosquitto
    		    ;;
            4) ###   KUMA UPTIME
                install_kuma
    		    ;;
            5) ###   BACK
                print_menu
                break
                ;;
            *)
                msg warning "Invalid option $REPLY"
                ;;
        esac
        REPLY=
    done
}

# --------------------          AUDIO          -------------------- #
install_audio() {
    PS3='Select Application for Download: '
    audio_options=("Logitech Media Server" "Back")
    select audio_opt in "${audio_options[@]}"
    do
        case $REPLY in
            1) ###   LOGITECH MEDIA SERVER
                install_lms
    		    ;;
            2) ###   BACK
                print_menu
                break
                ;;
            *)
                msg warning "Invalid option $REPLY"
                ;;
        esac
        REPLY=
    done
}

# --------------------          SECURITY          -------------------- #
install_security() {
    PS3='Select Application for Download: '
    security_options=("Frigate" "Back")
    select security_opt in "${security_options[@]}"
    do
        case $REPLY in
            1) ###   FRIGATE
                install_frigate
    		;;
            2)  ###   BACK
                print_menu
                break
                ;;
            *)
                msg warning "Invalid option $REPLY"
                ;;
        esac
        REPLY=
    done
}

# --------------------          NETWORK          -------------------- #
install_network() {
    PS3='Select Application for Download: '
    network_options=("Cloudflared" "Duck DNS" "Apache Web Server" "WireGuard" "Pi Hole" "Traefik" "Back")
    select network_opt in "${network_options[@]}"
    do
        case $REPLY in
            1)  ###   CLOUDFLARED
                install_cloudflared
    		;;
            2)  ###   DUCK DNS
                install_duckdns
    		;;
            3)  ###   APACHE WEB SERVER
                install_apache
    		;;
            4)  ###   WIREGUARD SERVER
                install_wireguard
    		;;
            5)  ###   PI HOLE SERVER
                install_pihole
    		;;
            6) ###   TRAEFIK
                install_traefik
                ;;
            7) ###   BACK
                print_menu
                break
                ;;
            *)
                msg warning "Invalid option $REPLY"
                ;;
        esac
        REPLY=
    done
}

# --------------------          POWER          -------------------- #
install_power() {
    PS3='Select Application for Download: '
    power_options=("Nut UPS Tool" "Back")
    select power_opt in "${power_options[@]}"
    do
        case $REPLY in
            1) ###   NUT
                install_NUT
                ;;
            2) ###   BACK
                print_menu
                break
                ;;
            *)
                msg warning "Invalid option $REPLY"
                ;;
        esac
        REPLY=
    done
}

# --------------------          SETTINGS          -------------------- #
install_settings() {
    PS3='Select System Application/Setting: '
    settings_options=("FTP" "Docker" "Back")
    select settings_opt in "${settings_options[@]}"
    do
        case $REPLY in
            1) ###   FTP
                install_FTP
                ;;
            2) ###   DOCKER
            	install_docker
                ;;
            3) ###   BACK
                print_menu
                break
                ;;
            *)
                msg warning "Invalid option $REPLY"
                ;;
        esac
        REPLY=
    done
}

###############################################################################################################
###                                            PROGRAM START                                                 ##
###############################################################################################################
main() {
    ###   Startup
    startup

    PS3='Select System for Download: '
    options=("Automation" "Audio" "Security" "Network" "Power" "Settings" "Full Install" "Quit")
    select opt in "${options[@]}"
    do
        case $REPLY in
            1)
                print_menu
                install_automation
                ;;
            2)
                print_menu
                install_audio
                ;;
            3)
                print_menu
                install_security
                ;;
            4)
                print_menu
                install_network
                ;;
            5)
                print_menu
                install_power
                ;;
            6)
                print_menu
                install_settings
                ;;
            7)
        	    print_menu
                install_full
                ;;
            8)
                shutdown
                ;;
            *)
                msg warning "Invalid option $REPLY"
                ;;
        esac
        REPLY=
    done
}

main
