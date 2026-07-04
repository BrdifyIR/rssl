#!/bin/bash

# Configuration File Path
CONFIG_FILE="/etc/rssl_config.conf"

# Function definitions for colored output
colors=( "\033[1;31m" "\033[1;35m" "\033[1;92m" "\033[38;5;46m" "\033[1;38;5;208m" "\033[1;36m" "\033[0m" )
red=${colors[0]} pink=${colors[1]} green=${colors[2]} spring=${colors[3]} orange=${colors[4]} cyan=${colors[5]} reset=${colors[6]}
print() { echo -e "${cyan}$1${reset}"; }
error() { echo -e "${red}✗ $1${reset}"; }
success() { echo -e "${spring}✓ $1${reset}"; }
log() { echo -e "${green}! $1${reset}"; }
warn() { echo -e "${orange} $1${reset}"; }

# Function to load Telegram config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Function to manage/setup Telegram Bot from Menu
setup_telegram_bot() {
    print "--- تنظیمات ربات تلگرام ---"
    echo -ne "${orange}توکن ربات تلگرام (Bot Token) را وارد کنید: ${reset}"
    read -r input_token
    echo -ne "${orange}آیدی عددی تلگرام (Chat ID) را وارد کنید: ${reset}"
    read -r input_chat_id

    if [[ -z "$input_token" || -z "$input_chat_id" ]]; then
        error "توکن یا چت آیدی نمی‌تواند خالی باشد!"
        return 1
    fi

    # Save to config file
    echo "BOT_TOKEN=\"$input_token\"" > "$CONFIG_FILE"
    echo "CHAT_ID=\"$input_chat_id\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    
    BOT_TOKEN="$input_token"
    CHAT_ID="$input_chat_id"
    
    success "تنظیمات تلگرام با موفقیت در $CONFIG_FILE ذخیره شد."
    
    # Restart daemon if it is installed
    if [ -f "/usr/local/bin/rssl_bot_daemon.sh" ]; then
        log "در حال راه‌اندازی مجدد سرویس ربات تلگرام..."
        pkill -f "rssl_bot_daemon.sh"
        start_telegram_daemon
    fi
}

# Function to remove Telegram Bot configuration
remove_telegram_bot() {
    log "در حال حذف تنظیمات ربات تلگرام و غیرفعال‌سازی سرویس..."
    
    # Stop daemon process
    if pgrep -f "rssl_bot_daemon.sh" > /dev/null; then
        pkill -f "rssl_bot_daemon.sh"
    fi
    
    # Remove background daemon script
    if [ -f "/usr/local/bin/rssl_bot_daemon.sh" ]; then
        rm -f "/usr/local/bin/rssl_bot_daemon.sh"
    fi
    
    # Remove config file
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
    fi
    
    # Clear active script variables
    BOT_TOKEN=""
    CHAT_ID=""
    
    success "ربات تلگرام با موفقیت حذف شد. دیگر هیچ پیامی ارسال نخواهد شد."
}

# Function to show the Brdify banner
show_banner() {
    echo -e "${pink}██████╗ ██████╗ ██████╗ ██╗██████╗ ██╗   ██╗${reset}"
    echo -e "${pink}██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗╚██╗ ██╔╝${reset}"
    echo -e "${pink}██████╔╝██████╔╝██║  ██║██║██████╔╝ ╚████╔╝ ${reset}"
    echo -e "${pink}██╔══██╗██╔══██╗██║  ██║██║██╔═══╝   ╚██╔╝  ${reset}"
    echo -e "${pink}██████╔╝██║  ██║██████╔╝██║██║        ██║   ${reset}"
    echo -e "${pink}╚══════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝        ╚═╝   ${reset}"
    echo -e "${cyan}Telegram Group: https://t.me/Brdify${reset}"
    echo -e "--------------------------------------------------"
}

# Trap for script interruption
trap 'echo -e "\n${red}Script interrupted!${reset}"; exit 1' SIGINT

# Validate domain format
validate_domain() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain format: $1"
        return 1
    fi
    return 0
}

# Function to send messages to Telegram
send_telegram_notification() {
    local message="$1"
    load_config
    if [ -z "$BOT_TOKEN" ]; then return 0; fi
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null
}

# Function to send Telegram message with Inline Keyboard for Renewal
send_telegram_renewal_prompt() {
    local main_domain="$1"
    local email="$2"
    local dest="$3"
    shift 3
    local domains=("$@")
    
    load_config
    if [ -z "$BOT_TOKEN" ]; then return 0; fi

    local encoded_domains=$(echo "${domains[*]}" | tr ' ' ',')
    local callback_data="renew:${email}:${dest}:${encoded_domains}"
    
    if [ ${#callback_data} -gt 60 ]; then
        callback_data="renew_fast:${main_domain}"
    fi

    local keyboard="{\"inline_keyboard\":[[{\"text\":\"🔄 تایید و تمدید گواهی SSL\",\"callback_data\":\"$callback_data\"}]]}"
    local text="⚠️ <b>هشدار تمدید SSL</b>%0A%0Aزمان تمدید گواهی دامنه <b>$main_domain</b> فرا رسیده است.%0Aجهت تمدید خودکار روی دکمه زیر کلیک کنید."

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" > /dev/null
}

# Function to install necessary dependencies
install_dependencies() {
    local pkg_manager
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
    else
        error "No supported package manager found."
        exit 1
    fi

    log "Updating package lists..."
    $pkg_manager update -y || warn "Failed to update package lists."

    local packages=("curl" "socat" "certbot" "jq")
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            log "Installing $pkg..."
            $pkg_manager install -y "$pkg" || error "Failed to install $pkg"
        fi
    done

    if ! command -v acme.sh &> /dev/null; then
        log "Installing acme.sh..."
        curl https://get.acme.sh | sh -s email="$email" || error "Failed to install acme.sh"
        source ~/.bashrc
    fi
    success "Dependencies are installed."
}

# Function to obtain and install SSL certificate using acme.sh
get_install_certificate_acme() {
    local domains=("$@")
    local domain_args=""
    local main_domain="${domains[0]}"

    for domain in "${domains[@]}"; do
        domain=$(echo "$domain" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        domain_args+=" -d $domain"
    done

    ~/.acme.sh/acme.sh --issue --standalone $domain_args --accountemail "$email" --force || return 1

    local cert_dir="$destination"
    mkdir -p "$cert_dir" || error "Failed to create certificate directory"

    ~/.acme.sh/acme.sh --install-cert -d "$main_domain" \
        --key-file "$cert_dir/privkey.pem" \
        --fullchain-file "$cert_dir/fullchain.pem" || return 1

    success "SSL certificate obtained and installed using acme.sh"
    return 0
}

# Function to obtain and install SSL certificate using certbot
get_install_certificate_certbot() {
    local domains=("$@")
    local domain_args=""

    for domain in "${domains[@]}"; do
        domain=$(echo "$domain" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        domain_args+=" -d $domain"
    done

    certbot certonly --standalone $domain_args --non-interactive --agree-tos --email "$email" --force || return 1

    local main_domain="${domains[0]}"
    local cert_dir="$destination"
    mkdir -p "$cert_dir" || error "Failed to create certificate directory"

    cat /etc/letsencrypt/live/$main_domain/privkey.pem > "$cert_dir/privkey.pem"
    cat /etc/letsencrypt/live/$main_domain/fullchain.pem > "$cert_dir/fullchain.pem"

    success "SSL certificate obtained and installed using certbot"
    return 0
}

# Background Daemon function for Telegram Bot updates
start_telegram_daemon() {
    load_config
    if [ -z "$BOT_TOKEN" ]; then
        return 0
    fi

    local daemon_path="/usr/local/bin/rssl_bot_daemon.sh"
    
    cat << 'EOF' > "$daemon_path"
#!/bin/bash
CONFIG_FILE="/etc/rssl_config.conf"
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi
OFFSET=0

if [ -z "$BOT_TOKEN" ]; then exit 1; fi

while true; do
    UPDATES=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=30")
    if [ -n "$UPDATES" ]; then
        CALLBACK_QUERY=$(echo "$UPDATES" | jq -r '.result[] | select(.callback_query != null) | .callback_query')
        if [ -n "$CALLBACK_QUERY" ]; then
            CQ_ID=$(echo "$CALLBACK_QUERY" | jq -r '.id')
            CHAT_ID=$(echo "$CALLBACK_QUERY" | jq -r '.message.chat.id')
            DATA=$(echo "$CALLBACK_QUERY" | jq -r '.data')
            
            if [[ "$DATA" == renew:* ]]; then
                IFS=':' read -r action email dest domains_str <<< "$DATA"
                IFS=',' read -r -a domains_arr <<< "$domains_str"
                
                curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/answerCallbackQuery" -d "callback_query_id=${CQ_ID}&text=تمدید آغاز شد..."
                curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${CHAT_ID}&text=🔄 فرآیند تمدید گواهی به صورت پس‌زمینه استارت خورد."
                
                /usr/local/bin/rssl "$email" "${domains_arr[@]}" "$dest"
            fi
        fi
        
        LAST_UPDATE_ID=$(echo "$UPDATES" | jq '.result[-1].update_id')
        if [ "$LAST_UPDATE_ID" != "null" ] && [ -n "$LAST_UPDATE_ID" ]; then
            OFFSET=$((LAST_UPDATE_ID + 1))
        fi
    fi
    sleep 2
done
EOF

    chmod +x "$daemon_path"
    
    if ! pgrep -f "rssl_bot_daemon.sh" > /dev/null; then
        nohup "$daemon_path" > /dev/null 2>&1 &
        success "سرویس پس‌زمینه ربات تلگرام با موفقیت فعال شد."
    fi
}

# Function to install the RSSL script
install_script() {
    log "Installing RSSL script..."
    local install_dir="/usr/local/bin"
    local script_path="$install_dir/rssl"

    cp "$0" "$script_path" 2>/dev/null
    chmod +x "$script_path"
    
    (crontab -l 2>/dev/null | grep -v "rssl"; echo "0 0 1 * * /usr/local/bin/rssl --cron-alert") | crontab -
    
    load_config
    if [ -z "$BOT_TOKEN" ]; then
        warn "تنظیمات ربات تلگرام یافت نشد."
        setup_telegram_bot
    fi
    
    start_telegram_daemon
    success "RSSL script and components installed successfully."
}

# Function to upgrade the RSSL script
upgrade_script() {
    log "Upgrading RSSL script..."
    local install_dir="/usr/local/bin"
    local script_path="$install_dir/rssl"

    if [ -f "$script_path" ]; then
        cp "$0" "$script_path"
        chmod +x "$script_path"
        success "RSSL script upgraded successfully."
    else
        error "RSSL script not found. Use '--install' to install it first."
    fi
}

# Function to uninstall the RSSL script
uninstall_script() {
    log "Uninstalling RSSL script..."
    local script_path="/usr/local/bin/rssl"
    if [ -f "$script_path" ]; then
        rm -f "$script_path"
        pkill -f "rssl_bot_daemon.sh"
        rm -f "/usr/local/bin/rssl_bot_daemon.sh"
        rm -f "$CONFIG_FILE"
        crontab -l 2>/dev/null | grep -v "rssl" | crontab -
        success "RSSL script and components removed successfully."
    else
        warn "RSSL script is not installed in /usr/local/bin/rssl"
    fi
}

# Function to display help message
show_help() {
    cat << EOF
Usage: rssl [email] [domain1 domain2 ...] <destination> | --install | --upgrade | --uninstall

Commands:
  --install         Install the RSSL script.
  --upgrade         Upgrade the RSSL script to the latest version.
  --uninstall       Uninstall the RSSL script from the system.
  --telegram        Setup or change Telegram Bot Token and Chat ID.
  --telegram-del    Remove Telegram Bot configuration and stop notification.
  --cron-alert      Trigger manual alert via cron to Telegram.
EOF
}

# Function for interactive SSL generation (Option 3)
interactive_ssl() {
    print "Select your Panel / Destination:"
    echo -e "  1) marzban"
    echo -e "  2) pasarguard"
    echo -e "  3) marzneshin"
    echo -e "  4) x-ui / 3x-ui / s-ui / hiddify"
    echo -e "  5) ovpanel"
    echo -e "  6) rebecca"
    echo -e "  7) Custom Path"
    echo -ne "${orange}Enter choice [1-7]: ${reset}"
    read -r p_choice

    local target_panel=""
    case "$p_choice" in
        1) target_panel="marzban" ;;
        2) target_panel="pasarguard" ;;
        3) target_panel="marzneshin" ;;
        4) target_panel="x-ui" ;;
        5) target_panel="ovpanel" ;;
        6) target_panel="rebecca" ;;
        7) 
            echo -ne "${orange}Enter custom absolute path: ${reset}"
            read -r target_panel
            ;;
        *) error "Invalid choice."; exit 1 ;;
    esac

    echo -ne "${orange}Enter your Email: ${reset}"
    read -r email
    echo -ne "${orange}Enter your Domains (separate with space): ${reset}"
    read -r -a domains

    issue_ssl_process "$email" "$target_panel" "${domains[@]}"
}

# Core logic function to issue SSL
issue_ssl_process() {
    local email="$1"
    local destination="$2"
    shift 2
    local domains=("$@")

    for domain in "${domains[@]}"; do
        validate_domain "$domain" || exit 1
    done

    case "$destination" in
        marzban) base_destination="/var/lib/marzban/certs" ;;
        marzneshin) base_destination="/var/lib/marzneshin/certs" ;;
        ovpanel) base_destination="/opt/ov-panel/data" ;;
        x-ui|3x-ui|s-ui|hiddify) base_destination="/certs" ;;
        pasarguard) base_destination="/var/lib/pasarguard/certs" ;;
        rebecca) base_destination="/var/lib/rebecca/certs" ;;
        *) base_destination="$destination" ;;
    esac

    install_dependencies
    first_domain="${domains[0]}"
    destination="${base_destination}/${first_domain}/"

    load_config
    if [ -z "$BOT_TOKEN" ]; then
        warn "تنظیمات تلگرام ست نشده است. پیام ارسال نخواهد شد."
    fi

    if get_install_certificate_acme "${domains[@]}"; then
        send_telegram_notification "✅ گواهی SSL برای دامنه $first_domain با موفقیت صادر/تمدید شد."
    else
        warn "Failed acme.sh. Trying certbot..."
        if get_install_certificate_certbot "${domains[@]}"; then
            send_telegram_notification "✅ گواهی SSL برای دامنه $first_domain با استفاده از Certbot تمدید شد."
        else
            error "Failed both."
            send_telegram_notification "❌ خطا در تمدید گواهی SSL دامنه $first_domain"
            exit 1
        fi
    fi
}

# Interactive menu function
show_interactive_menu() {
    print "Please choose an option:"
    echo -e "${spring}1)${reset} Install RSSL Script"
    echo -e "${spring}2)${reset} Uninstall RSSL Script"
    echo -e "${spring}3)${reset} Get SSL Certificate (Interactive)"
    echo -e "${spring}4)${reset} Setup/Change Telegram Bot Configuration"
    echo -e "${spring}5)${reset} Remove/Disable Telegram Bot"
    echo -e "${spring}6)${reset} Show Help Manual"
    echo -e "${spring}7)${reset} Exit"
    echo -ne "${orange}Enter choice [1-7]: ${reset}"
    read -r choice

    case "$choice" in
        1) install_script; exit 0 ;;
        2) uninstall_script; exit 0 ;;
        3) interactive_ssl; exit 0 ;;
        4) setup_telegram_bot; exit 0 ;;
        5) remove_telegram_bot; exit 0 ;;
        6) show_help; exit 0 ;;
        7) exit 0 ;;
        *) error "Invalid option."; exit 1 ;;
    esac
}

# Main function
main() {
    [ "$EUID" -eq 0 ] || { error "This script must be run as root."; exit 1; }
    load_config

    case "$1" in
        --install) install_script; exit 0 ;;
        --upgrade) upgrade_script; exit 0 ;;
        --uninstall) uninstall_script; exit 0 ;;
        --telegram) setup_telegram_bot; exit 0 ;;
        --telegram-del) remove_telegram_bot; exit 0 ;;
        --help|-h) show_help; exit 0 ;;
        --version|-v) print "current rssl version: v4.2.0"; exit 0 ;;
        --cron-alert)
            send_telegram_renewal_prompt "yourdomain.com" "user@example.com" "x-ui" "yourdomain.com"
            exit 0
            ;;
    esac

    if [ $# -lt 3 ]; then
        error "Not enough arguments."
        exit 1
    fi

    local email_cli="$1"
    shift
    local dest_cli="${@: -1}"
    local domains_cli=("${@:1:$#-1}")
    
    issue_ssl_process "$email_cli" "$dest_cli" "${domains_cli[@]}"
}

if [ $# -eq 0 ]; then
    show_banner
    show_interactive_menu
else
    show_banner
    main "$@"
fi
