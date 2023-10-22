#!/bin/bash

##########################################
###             FUNCTIONS              ###
##########################################

###   PRINT MENU   ###
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

###   ERROR MESSENGER   ###
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

###   STARTUP   ###
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

###   SHUTDOWN   ###
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

##########################################
###             INSTALLERS             ###
##########################################

###   HOME ASSISTANT INSTALLER   ###
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
      - "80:8123"
    restart: unless-stopped
    privileged: true
    networks:
      - homenet

EOL
        msg success "Home Assistant configuration added to docker-compose.yaml"
    else
        msg warning "Home Assistant entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
            
    if docker ps | grep -q "homeassistant"; then
        print_menu
        msg success "Home Assistant successfully installed and running"
	msg info "http://localhost:80\n"
    else
        print_menu
        msg error "Home Assistant container failed to start\n"
    fi
}

###   NODE RED INSTALLER   ###
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
	msg info "http://localhost:1880\n"
    else
        print_menu
        msg error "Node-RED container failed to start\n"
    fi
}

prep_nodered(){
     docker exec -it nodered npm install node-red-contrib-home-assistant-websocket
     docker restart nodered
}

### MOSQUITTO MQTT INSTALLER ###
install_mosquitto() {
    check_docker
    clear
    msg info "Installing Mosquitto MQTT..."
    if ! grep -q "mosquitto:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  mosquitto:
    container_name: mosquitto
    image: "eclipse-mosquitto"
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
        sudo mkdir /opt/mosquitto | sudo mkdir /opt/mosquitto/config | sudo touch /opt/mosquitto/config/mosquitto.conf
    
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
	msg info "http://localhost:1883\n"
    else
        print_menu
        msg error "Mosquitto container failed to start\n"
    fi
}

### KUMA UPTIME INSTALLER ###
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
    restart: always

EOL
        msg success "Kuma configuration added to docker-compose.yaml"
    else
        msg warning "Kuma entry already exists in docker-compose.yaml"
    fi
    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    if docker ps | grep -q "kuma"; then
        print_menu
        msg success "Kuma successfully installed and running"
	msg info "http://localhost:3001\n"
    else
        print_menu
        msg error "Kuma container failed to start\n"
    fi
}

###   LOGITECH MEDIA SERVER INSTALLER   ###
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
      - /opt/lms/config:/config:rw
      - /home/$(whoami)/Music:/music:ro
      - /home/$(whoami)/Music/playlists:/playlist:rw
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
  #  devices:
  #    - /dev/snd    # For Adding USB Sound Card for Line-In Audio Input
    ports:
      - 9000:9000/tcp
      - 9090:9090/tcp
      - 3483:3483/tcp
      - 3483:3483/udp
    restart: always
    networks:
      - homenet

EOL
        msg success "Logitech Media Server configuration added to docker-compose.yaml"
    else
        msg warning "Logitech Media Server entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
            
    if docker ps | grep -q "logitechmediaserver"; then
        print_menu
        msg success "Logitech Media Server successfully installed and running"
	msg info "http://localhost:9000\n"
    else
        print_menu
        msg error "Logitech Media Server container failed to start\n"
    fi
}

###   FRIGATE INSTALLER   ###
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

EOL
        msg success "Frigate NVR configuration added to docker-compose.yaml"
    else
        msg warning "Frigate NVR entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
            
    if docker ps | grep -q "frigate"; then
        print_menu
        msg success "Frigate NVR successfully installed and running"
	msg info "http://localhost:5000\n"
    else
        print_menu
        msg error "Frigate NVR container failed to start\n"
    fi
}

###   WEB RTC INSTALLER   ###
#install_webRTC() {
    # Script to install Web RTC
#}

###   CLOUDFLARED INSTALLER   ###
install_cloudflared() {
    clear
    msg info "Installing Cloudflared..."
                
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

	echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

	sudo apt-get update && sudo apt-get install cloudflared

	clear
    msg success "Cloudflared downloaded successfully\n"

	# Execute cloudflared login (this will open a browser for login)
	cloudflared login
		
	clear
    msg success "Login Successful\n"
		
	# Prompt for Tunnel Name
	while [[ -z $TUNNEL_NAME ]]; do
		msg info "Enter the tunnel name: "
		read TUNNEL_NAME
	done

	# Create a tunnel and capture the Tunnel UUID
	TUNNEL_UUID=$(cloudflared tunnel create $TUNNEL_NAME | awk '/Created tunnel/{print $NF}')

	# Check if Tunnel UUID was captured
	if [[ -z $TUNNEL_UUID ]]; then
		msg error "Failed to obtain Tunnel UUID. Exiting."
		exit 1
	fi

	# Create & Route Sub Domain
   	cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_NAME

	# Define the path to the credentials file using the Tunnel UUID
	CREDENTIALS_FILE_PATH="$HOME/.cloudflared/$TUNNEL_UUID.json"

	# Create the config.yml file with the necessary parameters
    cat <<EOL > ~/.cloudflared/config.yml
url: localhost:80
tunnel: $TUNNEL_UUID
credentials-file: $CREDENTIALS_FILE_PATH
EOL
   		
   	clear
   		
   	cloudflared tunnel --config ~/.cloudflared/config.yml run > /dev/null 2>&1 &
   		
   	if crontab -l | grep -q "cloudflared tunnel"; then
	    msg info "Command is already in crontab"
	else
	    # Add the command to crontab to run it at reboot
	    (crontab -l 2>/dev/null; echo "@reboot cloudflared tunnel --config ~/.cloudflared/config.yml run") | crontab -
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

###   APACHE WEB SERVER INSTALLER   ###
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
    - '8080:8080'
    volumes:
    - /opt/apache/website:/usr/local/apache2/htdocs
    networks:
      - homenet

EOL
        msg success "Apache configuration added to docker-compose.yaml"
    else
        msg warning "Apache entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    		
    if docker ps | grep -q "apache"; then
        print_menu
        msg success "Apache Web Server successfully installed and running"
	msg info "http://localhost:8080\n"
	else
        print_menu
	    msg error "Apache Web Server failed to start\n"
	fi
}

### DUCKDNS INSTALLER ###
install_duckdns() {
    check_docker
    clear
    msg info "Installing DuckDNS..."
    if ! grep -q "duckdns:" /opt/docker-compose.yaml; then
    
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

### WIREGUARD INSTALLER ###
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
        - /lib/modules:/lib/modules
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

### TRAEFIK INSTALLER ###
install_traefik() {
    check_docker
    clear
    msg info "Installing Traefik..."
    if ! grep -q "traefik:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  traefik:
    container_name: traefik
    image: "traefik"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/traefik:/etc/traefik
    networks:
      - homenet
    labels:
      - "traefik.enable=true"                                                                       # Enable Traefik for this container
#      - "traefik.http.routers.traefik.entrypoints=http"                                             # Specify HTTP entrypoint
#      - "traefik.http.routers.traefik.rule=Host(`traefik-dashboard.local.example.com`)"             # Set rule for router
#      - "traefik.http.middlewares.traefik-auth.basicauth.users=USER:BASIC_AUTH_PASSWORD"            # Basic authentication
#      - "traefik.http.middlewares.traefik-https-redirect.redirectscheme.scheme=https"               # HTTPS redirect
#      - "traefik.http.middlewares.sslheader.headers.customrequestheaders.X-Forwarded-Proto=https"   # Set header for SSL
#      - "traefik.http.routers.traefik.middlewares=traefik-https-redirect"                           # Apply HTTPS redirect middleware
#      - "traefik.http.routers.traefik-secure.entrypoints=https"                                     # Specify HTTPS entrypoint
#      - "traefik.http.routers.traefik-secure.rule=Host(`traefik-dashboard.local.example.com`)"      # Set rule for secure router
#      - "traefik.http.routers.traefik-secure.middlewares=traefik-auth"                              # Apply auth middleware
#      - "traefik.http.routers.traefik-secure.tls=true"                                              # Enable TLS
#      - "traefik.http.routers.traefik-secure.tls.certresolver=cloudflare"                           # Set certificate resolver
#      - "traefik.http.routers.traefik-secure.tls.domains[0].main=local.example.com"                 # Set main domain for TLS
#      - "traefik.http.routers.traefik-secure.tls.domains[0].sans=*.local.example.com"               # Set SANs for TLS
#      - "traefik.http.routers.traefik-secure.service=api@internal"                                  # Set service for secure router
      
EOL
        msg success "Traefik configuration added to docker-compose.yaml"
    else
        msg warning "Traefik entry already exists in docker-compose.yaml"
    fi
    docker-compose -f /opt/docker-compose.yaml up -d
    if docker ps | grep -q "traefik"; then
        print_menu
        msg success "Traefik successfully installed and running"
	msg info "http://localhost:80\n"
    else
        print_menu
        msg error "Traefik container failed to start\n"
    fi
}

### ADGUARD INSTALLER ###
install_adguard() {
    check_docker
    clear
    msg info "Installing AdGuard..."
    if ! grep -q "adguard:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  adguard:
    container_name: adguard
    image: "adguard/adguardhome"
    volumes:
        - /opt/adguard/work:/opt/adguardhome/work
        - /opt/adguard/conf:/opt/adguardhome/conf
#	- /opt/shared/certs/example.com:/certs # optional: if you have your own SSL cert
    ports:
        - "53:53/tcp"
        - "53:53/udp"
        - "67:67/udp"
        - "68:68/tcp"
        - "800:80/tcp"
        - "443:443/tcp"
        - "853:853/tcp"
        - "3000:3000/tcp" # For Initial Setup
    restart: unless-stopped
    network_mode: host

EOL
        msg success "AdGuard configuration added to docker-compose.yaml"
    else
        msg warning "AdGuard entry already exists in docker-compose.yaml"
    fi

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans

    sudo systemctl disable systemd-resolved.service     # Disable DNS Service on Port 53
    sudo systemctl stop systemd-resolved                # This will require a reboot

    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans

    prep_adguard
    
    if docker ps | grep -q "adguard"; then
        print_menu
        msg success "AdGuard successfully installed and running"
	msg info "http://localhost:800\n"
    else
        print_menu
        msg error "AdGuard container failed to start\n"
    fi
}

### ADGUARD PREP ###
prep_adguard() {
    clear
    msg info "Web UI for AdGuard Startup Will Now Open"
    echo "Enter Web Interface Port: 800"
    echo "Leave DNS Port: 53"
    echo "URL: http://localhost:3000"
    python -m webbrowser "https://localhost:3000"
    echo "Press any key to continue."
    read -n1 -s
    echo "Waiting for Web Setup to Complete"

    # Wait for a specific file to appear
    while [[ ! -f /opt/adguard/config/AdGuardHome.yaml ]]; do
        sleep 3
    done

    # Continue with the rest of your script
    msg success "Setup Complete, continuing..."
}

###   NUT INSTALLER   ###
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
    		
    if docker ps | grep -q "apache"; then
        print_menu
        msg success "NUT Server successfully installed and running\n"
	else
        print_menu
		msg error "NUT Server failed to start\n"
	fi
}

###   FTP INSTALLER   ###
install_FTP() {
    clear
    msg info "Configuring FTP..."
                
    sudo apt-get install -y vsftpd
                
    sudo rm /etc/vsftpd.conf
                
	sudo touch /etc/vsftpd.conf
              
    msg success "FTP Successfully Configured."
                
    sleep 1
                
    clear
                
	sudo mkdir /etc/ssl/private
	sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/vsftpd.pem -out /etc/ssl/private/vsftpd.pem
                
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

###   DOCKER INSTALLER   ###
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
        cat <<'EOL' >> /opt/docker-compose.yaml  # Start of here-document
version: '3.9'

networks:
  homenet:
    driver: bridge

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

### PORTAINER INSTALLER ###
install_portainer() {
    check_docker
    clear
    msg info "Installing Portainer..."
    if ! grep -q "portainer:" /opt/docker-compose.yaml; then
        cat << EOL >> /opt/docker-compose.yaml
  portainer:
    image: portainer/portainer-ce:latest
    ports:
      - 9443:9443
    volumes:
      - /opt/portainer/data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

EOL
        msg success "Portainer configuration added to docker-compose.yaml"
    else
        msg warning "Portainer entry already exists in docker-compose.yaml"
    fi
    
    docker-compose -f /opt/docker-compose.yaml up -d --remove-orphans
    
    if docker ps | grep -q "portainer"; then
        print_menu
        msg success "Portainer successfully installed and running"
	python -m webbrowser "https://localhost:9443"
	msg info "https://localhost:9443\n"
    else
        print_menu
        msg error "Portainer container failed to start\n"
    fi
}

###   FULL INSTALLER   ###
additional_applications() {
    PS3='Select additional applications to install: '
    additional_options=("Cloudflared" "Apache Web Server" "Frigate NVR" "WebRTC" "Logitech Media Server" "NUT UPS Tool" "Done")
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
            "WebRTC")
                install_webRTC
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


##########################################
###          INSTALL CHECKERS          ###
##########################################

###   HOME ASSISTANT CHECK   ###
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

###   DOCKER CHECK   ###
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


##########################################
###              SUB-MENUS             ###
##########################################

###   AUTOMATION   ###
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

###   AUDIO   ###
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

###   SECURITY   ###
install_security() {
    PS3='Select Application for Download: '
    security_options=("Frigate" "WebRTC" "Back")
    select security_opt in "${security_options[@]}"
    do
        case $REPLY in
            1) ###   FRIGATE
                install_frigate
    		    ;;
            2)  ###   WEB RTC
                install_webRTC
                ;;
            3)  ###   BACK
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

###   NETWORK   ###
install_network() {
    PS3='Select Application for Download: '
    network_options=("Cloudflared" "Duck DNS" "Apache Web Server" "WireGuard" "AdGuard" "Traefik" "Back")
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
            5)  ###   ADGUARD SERVER
                install_adguard
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

###   POWER   ###
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

###   SETTINGS   ###
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

##########################################
###            PROGRAM START           ###
##########################################
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
