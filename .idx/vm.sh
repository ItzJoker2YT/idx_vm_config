#!/bin/bash
set -euo pipefail

# =================================================================
#  ULTIMATE VM MANAGER - INSTANT CONNECT EDITION
# =================================================================

# --- 1. DEFINE COLORS ---
RESET='\033[0m'
BLACK='\033[0;30m'  RED='\033[0;31m'    GREEN='\033[0;32m'
YELLOW='\033[0;33m' BLUE='\033[0;34m'   PURPLE='\033[0;35m'
CYAN='\033[0;36m'   WHITE='\033[0;37m'

B_BLACK='\033[1;30m' B_RED='\033[1;31m'   B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m' B_BLUE='\033[1;34m'  B_PURPLE='\033[1;35m'
B_CYAN='\033[1;36m'  B_WHITE='\033[1;37m'

BG_BLACK='\033[40m'  BG_RED='\033[41m'    BG_GREEN='\033[42m'
BG_YELLOW='\033[43m' BG_BLUE='\033[44m'   BG_PURPLE='\033[45m'
BG_CYAN='\033[46m'   BG_WHITE='\033[47m'

# --- 2. CONFIGURATION ---
VM_DIR="$HOME/vms"
mkdir -p "$VM_DIR"

ICON_VM="💾"
ICON_ROCKET="🚀"
ICON_BOX="📦"
ICON_GEAR="⚙️"
ICON_CHECK="✅"
ICON_ERROR="❌"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
ICON_TELE="📡"
ICON_RDP="🖥️"

# --- 3. UTILITIES ---

print_status() {
    local type=$1
    local message=$2
    case $type in
        "INFO") echo -e "\033[1;34m[ℹ️ INFO]\033[0m  $message" ;;
        "WARN") echo -e "\033[1;33m[⚠️ WARN]\033[0m  $message" ;;
        "ERROR") echo -e "\033[1;31m[❌ ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[✅ OK]\033[0m    $message" ;;
        "INPUT") echo -e "\033[1;36m[👉 INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

check_port_open() {
    # Pure Bash TCP check (Very fast)
    (echo > /dev/tcp/127.0.0.1/$1) >/dev/null 2>&1
}

validate_input() {
    local type=$1
    local value=$2
    case $type in
        "number") [[ "$value" =~ ^[0-9]+$ ]] || return 1 ;;
        "size") [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || return 1 ;;
        "port") [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 23 ] && [ "$value" -le 65535 ] || return 1 ;;
        "name") [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1 ;;
        "username") [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1 ;;
    esac
    return 0
}

check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "openssl" "sshpass" "nc")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then missing+=("$dep"); fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing[*]}"
        print_status "WARN" "Please rebuild your dev.nix environment!"
        exit 1
    fi
}

display_header() {
    clear
    echo -e "${B_GREEN}"
    cat << "EOF"
      ██╗░█████╗░██╗░░██╗███████╗██████╗░░██████╗
      ██║██╔══██╗██║░██╔╝██╔════╝██╔══██╗██╔════╝
      ██║██║░░██║█████═╝░█████╗░░██████╔╝╚█████╗░
 ██   ██║██║░░██║██╔═██╗░██╔══╝░░██╔══██╗░╚═══██╗
 ╚█████╔╝╚█████╔╝██║░╚██╗███████╗██║░░██║██████╔╝
  ╚════╝░░╚════╝░╚═╝░░╚═╝╚══════╝╚═╝░░╚═╝╚═════╝░

 ██╗░░░██╗███████╗██████╗░░██████╗██╗░█████╗░███╗░░██╗
 ██║░░░██║██╔════╝██╔══██╗██╔════╝██║██╔══██╗████╗░██║
 ╚██╗░██╔╝█████╗░░██████╔╝╚█████╗░██║██║░░██║██╔██╗██║
  ╚████╔╝░██╔══╝░░██╔══██╗░╚═══██╗██║██║░░██║██║╚████║
   ╚██╔╝░░███████╗██║░░██║██████╔╝██║╚█████╔╝██║░╚███║
    ╚═╝░░░╚══════╝╚═╝░░╚═╝╚═════╝░╚═╝░╚════╝░╚═╝░░╚══╝
EOF
    echo -e "${RESET}"
    echo -e "${B_YELLOW}             >>>  Ultimate VM Manager Tool  <<<    ${RESET}"
    echo -e "${B_BLUE}             ---------------------------------------------    ${RESET}"
    echo -e "                 ${B_PURPLE}Original VM Manager Script By Hopingboyz , Modified By Joker${RESET}"
    echo
}

cleanup() { rm -f "user-data" "meta-data"; }

# --- 4. STORAGE ENGINE ---

get_storage_candidates() {
    echo "$HOME/vms|Home Directory (Safe - 15GB)|persistent"
    echo "/mnt/vms_storage|Mounted Disk (Best - 46GB)|persistent"
    echo "/nix/vms_storage|Nix Overlay (25GB)|overlay"
    echo "/var/vms_storage|Var RAM Disk (16GB)|volatile"
    echo "/run/vms_storage|Run RAM Disk (16GB)|volatile"
}

select_storage_location() {
    print_status "INFO" "Scanning available storage pools..."
    echo -e "${B_BLUE}   #  LOCATION             AVAIL   USED%   TYPE        STATUS${RESET}"
    echo -e "${B_BLUE}   ------------------------------------------------------------${RESET}"

    local candidates=()
    local best_choice=1
    local max_avail=0
    local i=1

    while IFS='|' read -r path label type; do
        mkdir -p "$path" 2>/dev/null || true
        
        if [ -w "$path" ]; then
            local df_out=$(df -h "$path" | tail -1)
            local avail=$(echo "$df_out" | awk '{print $4}')
            local used_p=$(echo "$df_out" | awk '{print $5}')
            local avail_raw=$(df -k "$path" | tail -1 | awk '{print $4}')

            local color="$GREEN"
            local status_text="GOOD"
            
            if [[ "$used_p" == "100%" ]]; then color="$RED"; status_text="FULL";
            elif [[ "$type" == "volatile" ]]; then color="$YELLOW"; status_text="RISKY";
            elif [[ "$used_p" > "80%" ]]; then color="$YELLOW"; fi

            if [[ "$type" == "persistent" || "$type" == "overlay" ]] && [[ "$status_text" != "FULL" ]]; then
                if (( avail_raw > max_avail )); then max_avail=$avail_raw; best_choice=$i; fi
            fi

            printf "   ${color}%d) %-20s %-7s %-7s %-10s %s${RESET}\n" "$i" "${label:0:20}" "$avail" "$used_p" "$type" "$status_text"
            candidates[$i]="$path"
            ((i++))
        fi
    done < <(get_storage_candidates)

    echo
    print_status "INFO" "Recommendation: Option $best_choice has the most free space."
    while true; do
        read -p "$(print_status "INPUT" "Select storage ID (default: $best_choice): ")" sel
        sel="${sel:-$best_choice}"
        if [[ -n "${candidates[$sel]:-}" ]]; then
            SELECTED_STORAGE="${candidates[$sel]}"
            if [[ "$SELECTED_STORAGE" == *"/var"* || "$SELECTED_STORAGE" == *"/run"* ]]; then
                print_status "WARN" "RAM storage selected. DATA WILL VANISH on reboot!"
                read -p "Are you sure? (y/n): " confirm
                [[ "$confirm" != "y" ]] && continue
            fi
            mkdir -p "$SELECTED_STORAGE"
            print_status "SUCCESS" "Storage set to: $SELECTED_STORAGE"
            break
        else
            print_status "ERROR" "Invalid selection."
        fi
    done
}

# --- 5. CORE LOGIC ---

get_vm_list() { find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort; }

load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    if [[ -f "$config_file" ]]; then
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED STORAGE_PATH
        source "$config_file"
        if [[ -z "${STORAGE_PATH:-}" ]]; then STORAGE_PATH="$VM_DIR"; fi
        IMG_FILE="$STORAGE_PATH/$VM_NAME.img"
        SEED_FILE="$STORAGE_PATH/$VM_NAME-seed.iso"
        return 0
    else
        print_status "ERROR" "Config for '$vm_name' not found"
        return 1
    fi
}

save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
CREATED="$CREATED"
STORAGE_PATH="$SELECTED_STORAGE"
EOF
    print_status "SUCCESS" "Configuration saved to $config_file"
}

create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then print_status "ERROR" "VM exists"; else break; fi
        fi
    done

    read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
    HOSTNAME="${HOSTNAME:-$VM_NAME}"

    read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

    read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
    PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
    echo ""

    read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
    DISK_SIZE="${DISK_SIZE:-20G}"

    read -p "$(print_status "INPUT" "Memory in MB (default: 2048): ")" MEMORY
    MEMORY="${MEMORY:-2048}"

    read -p "$(print_status "INPUT" "Number of CPUs (default: 2): ")" CPUS
    CPUS="${CPUS:-2}"

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if check_port_open "$SSH_PORT"; then print_status "ERROR" "Port in use"; else break; fi
        fi
    done

    read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: n): ")" gui_input
    GUI_MODE=false; [[ "$gui_input" =~ ^[Yy]$ ]] && GUI_MODE=true

    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80): ")" PORT_FORWARDS

    echo
    print_status "INFO" "Determining best storage location..."
    select_storage_location
    
    IMG_FILE="$SELECTED_STORAGE/$VM_NAME.img"
    SEED_FILE="$SELECTED_STORAGE/$VM_NAME-seed.iso"
    CREATED="$(date)"

    setup_vm_image
    save_vm_config
}

setup_vm_image() {
    print_status "INFO" "Downloading and preparing image in $SELECTED_STORAGE..."
    mkdir -p "$SELECTED_STORAGE"
    
    if [[ ! -f "$IMG_FILE" ]]; then
        print_status "INFO" "Downloading image from $IMG_URL..."
        wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    qemu-img resize "$IMG_FILE" "$DISK_SIZE" >/dev/null 2>&1

    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    passwd: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
runcmd:
  - sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
  - sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - systemctl restart ssh
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
}

# --- THE IMPROVED START LOGIC ---
start_vm() {
    local vm_name=$1
    if ! load_vm_config "$vm_name"; then return; fi
    
    # 1. ZOMBIE CHECK (Running but closed port)
    if pgrep -f "$IMG_FILE" >/dev/null; then
        if ! check_port_open "$SSH_PORT"; then
            print_status "WARN" "VM process found, but Port $SSH_PORT is unresponsive."
            print_status "INFO" "Killing zombie process and restarting..."
            pkill -f "$IMG_FILE"
            sleep 1
        fi
    fi

    # 2. START IF NOT RUNNING
    if ! pgrep -f "$IMG_FILE" >/dev/null; then
        print_status "INFO" "Starting $VM_NAME..."
        
        if [[ ! -f "$SEED_FILE" ]]; then
            SELECTED_STORAGE="$STORAGE_PATH"
            setup_vm_image
        fi
        
        # Clear known_hosts to prevent "man in the middle" warnings on reconnect
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[localhost]:$SSH_PORT" >/dev/null 2>&1

        local qemu_cmd=(
            qemu-system-x86_64 -enable-kvm -m "$MEMORY" -smp "$CPUS" -cpu host
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot c
            -device virtio-net-pci,netdev=n0
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
            -display none -daemonize
        )

        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi
        
        "${qemu_cmd[@]}"
        print_status "SUCCESS" "VM Process Launched."
    else
        print_status "INFO" "VM is already running. Reconnecting..."
    fi

    # 3. SMART WAIT (Polls port every 1s)
    echo -n "Waiting for boot..."
    local attempts=0
    local max_attempts=45 # Wait up to 45 seconds
    while ! check_port_open "$SSH_PORT"; do
        sleep 1
        echo -n "."
        attempts=$((attempts+1))
        if [ $attempts -ge $max_attempts ]; then
            echo ""
            print_status "ERROR" "VM failed to boot within 45 seconds."
            return
        fi
    done
    echo " Ready!"

    # 4. INSTANT CONNECT (No Warning Messages)
    print_status "INFO" "Connecting..."
    
    # -o UserKnownHostsFile=/dev/null -> Don't save key (Avoids pollution)
    # -o StrictHostKeyChecking=no -> Don't ask yes/no
    # -o LogLevel=ERROR -> Hides "Warning: Permanently added..."
    local ssh_opts="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -p $SSH_PORT"
    
    if command -v sshpass &> /dev/null; then
        sshpass -p "$PASSWORD" ssh $ssh_opts "$USERNAME@localhost"
    else
        ssh $ssh_opts "$USERNAME@localhost"
    fi
}

is_vm_running() {
    local vm_name=$1
    if load_vm_config "$vm_name" >/dev/null 2>&1; then
        if pgrep -f "$IMG_FILE" >/dev/null; then return 0; fi
    fi
    return 1
}

stop_vm() {
    local vm_name=$1
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            pkill -f "$IMG_FILE"
            sleep 2
            if is_vm_running "$vm_name"; then pkill -9 -f "$IMG_FILE"; fi
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

delete_vm() {
    local vm_name=$1
    print_status "WARN" "Permanently delete '$vm_name'? (y/N)"
    read -p "$(print_status "INPUT" "Confirm: ")" confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM Deleted"
        fi
    fi
}

show_vm_info() {
    local vm_name=$1
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: $PASSWORD"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "Disk: $DISK_SIZE"
        echo "Location: $STORAGE_PATH"
        echo "=========================================="
        read -p "$(print_status "INPUT" "Press Enter...")"
    fi
}

resize_vm_disk() {
    local vm_name=$1
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current: $DISK_SIZE"
        read -p "$(print_status "INPUT" "New size (e.g., 50G): ")" new_size
        if validate_input "size" "$new_size"; then
            qemu-img resize "$IMG_FILE" "$new_size"
            DISK_SIZE="$new_size"
            SELECTED_STORAGE="$STORAGE_PATH"
            save_vm_config
            print_status "SUCCESS" "Resized to $new_size"
        fi
    fi
}

show_vm_performance() {
    local vm_name=$1
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            local pid=$(pgrep -f "$IMG_FILE")
            echo "Process Stats:"
            ps -p "$pid" -o pid,%cpu,%mem,rss,cmd --no-headers
            echo
            echo "Disk Usage:"
            df -h "$IMG_FILE"
        else
            print_status "INFO" "VM not running."
        fi
        read -p "$(print_status "INPUT" "Press Enter...")"
    fi
}

edit_vm_config() {
    local vm_name=$1
    if load_vm_config "$vm_name"; then
        print_status "WARN" "Editing config requires manual update in this version."
        print_status "INFO" "Edit file: $VM_DIR/$vm_name.conf"
        read -p "Press Enter..."
    fi
}

# --- 6. MAIN MENU ---

main_menu() {
    while true; do
        display_header
        local vms=($(get_vm_list))
        
        if [ ${#vms[@]} -gt 0 ]; then
            print_status "INFO" "Found ${#vms[@]} existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if is_vm_running "${vms[$i]}"; then status="Running"; fi
                if load_vm_config "${vms[$i]}" >/dev/null 2>&1; then
                    local loc=$(basename "$STORAGE_PATH")
                    printf "  %2d) %-15s [%s] @ %s\n" $((i+1)) "${vms[$i]}" "$status" "$loc"
                fi
            done
            echo
        fi
        
        echo -e " ${B_WHITE}${BG_BLUE} MAIN MENU ${RESET}"
        echo
        echo -e " ${B_CYAN}1${RESET} ${ICON_VM}  ${B_GREEN}Create a new VM${RESET}"
        if [ ${#vms[@]} -gt 0 ]; then
            echo -e " ${B_CYAN}2${RESET} ${ICON_ROCKET}  ${B_GREEN}Start a VM${RESET}"
            echo -e " ${B_CYAN}3${RESET} ${ICON_WARN}  ${B_YELLOW}Stop a VM${RESET}"
            echo -e " ${B_CYAN}4${RESET} ${ICON_INFO}  ${B_BLUE}Show VM info${RESET}"
            echo -e " ${B_CYAN}5${RESET} ${ICON_GEAR}  ${B_PURPLE}Edit VM configuration${RESET}"
            echo -e " ${B_CYAN}6${RESET} ${ICON_ERROR}  ${B_RED}Delete a VM${RESET}"
            echo -e " ${B_CYAN}7${RESET} ${ICON_BOX}  ${B_CYAN}Resize VM disk${RESET}"
            echo -e " ${B_CYAN}8${RESET} ${ICON_TELE}  ${B_WHITE}Show VM performance${RESET}"
        fi
        echo -e " ${B_RED}0${RESET} ${ICON_ERROR}  ${B_RED}Exit${RESET}"
        echo
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1) create_new_vm ;;
            2) 
                read -p "$(print_status "INPUT" "Enter VM number to start: ")" num
                [[ "$num" =~ ^[0-9]+$ ]] && start_vm "${vms[$((num-1))]}" 
                ;;
            3)
                read -p "$(print_status "INPUT" "Enter VM number to stop: ")" num
                [[ "$num" =~ ^[0-9]+$ ]] && stop_vm "${vms[$((num-1))]}" 
                ;;
            4)
                read -p "$(print_status "INPUT" "Enter VM number to show info: ")" num
                [[ "$num" =~ ^[0-9]+$ ]] && show_vm_info "${vms[$((num-1))]}" 
                ;;
            5)
                read -p "$(print_status "INPUT" "Enter VM number to edit: ")" num
                [[ "$num" =~ ^[0-9]+$ ]] && edit_vm_config "${vms[$((num-1))]}" 
                ;;
            6)
                read -p "$(print_status "INPUT" "Enter VM number to delete: ")" num
                [[ "$num" =~ ^[0-9]+$ ]] && delete_vm "${vms[$((num-1))]}" 
                ;;
            7)
                read -p "$(print_status "INPUT" "Enter VM number to resize: ")" num
                [[ "$num" =~ ^[0-9]+$ ]] && resize_vm_disk "${vms[$((num-1))]}" 
                ;;
            8)
                read -p "$(print_status "INPUT" "Enter VM number for perf: ")" num
                [[ "$num" =~ ^[0-9]+$ ]] && show_vm_performance "${vms[$((num-1))]}" 
                ;;
            0) exit 0 ;;
            *) print_status "ERROR" "Invalid selection" ;;
        esac
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

trap cleanup EXIT
check_dependencies

declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

main_menu
