#!/bin/bash

# Function definitions for colored output
colors=( "\033[1;31m" "\033[1;35m" "\033[1;92m" "\033[38;5;46m" "\033[1;38;5;208m" "\033[1;36m" "\033[0m" )
red=${colors[0]} pink=${colors[1]} green=${colors[2]} spring=${colors[3]} orange=${colors[4]} cyan=${colors[5]} reset=${colors[6]}
print() { echo -e "${cyan}$1${reset}"; }
error() { echo -e "${red}✗ $1${reset}"; }
success() { echo -e "${spring}✓ $1${reset}"; }
log() { echo -e "${green}! $1${reset}"; }
warn() { echo -e "${orange} $1${reset}"; }

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
        error "No supported package manager found. Please install packages manually."
        exit 1
    fi

    log "Updating package lists..."
    $pkg_manager update -y || warn "Failed to update package lists."

    local packages=("curl" "socat" "certbot")
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

# Function to obtain and install SSL certificate using acme.sh for multiple domains
get_install_certificate_acme() {
    local domains=("$@")
    local domain_args=""
    local main_domain="${domains[0]}"

    for domain in "${domains[@]}"; do
        domain=$(echo "$domain" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        domain_args+=" -d $domain"
    done

    ~/.acme.sh/acme.sh --issue --standalone $domain_args --accountemail "$email" || return 1

    local cert_dir="$destination"
    mkdir -p "$cert_dir" || error "Failed to create certificate directory"

    ~/.acme.sh/acme.sh --install-cert -d "$main_domain" \
        --key-file "$cert_dir/privkey.pem" \
        --fullchain-file "$cert_dir/fullchain.pem" || return 1

    success "SSL certificate obtained and installed using acme.sh for domains: ${domains[*]}"
    return 0
}

# Function to obtain and install SSL certificate using certbot for multiple domains
get_install_certificate_certbot() {
    local domains=("$@")
    local domain_args=""

    for domain in "${domains[@]}"; do
        domain=$(echo "$domain" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        domain_args+=" -d $domain"
    done

    certbot certonly --standalone $domain_args --non-interactive --agree-tos --email "$email" || return 1

    local main_domain="${domains[0]}"
    local cert_dir="$destination"
    mkdir -p "$cert_dir" || error "Failed to create certificate directory"

    cat /etc/letsencrypt/live/$main_domain/privkey.pem > "$cert_dir/privkey.pem"
    cat /etc/letsencrypt/live/$main_domain/fullchain.pem > "$cert_dir/fullchain.pem"

    success "SSL certificate obtained and installed using certbot for domains: ${domains[*]}"
    return 0
}

# Function to install the RSSL script
install_script() {
    log "Installing RSSL script..."
    local install_dir="/usr/local/bin"
    local script_path="$install_dir/rssl"

    curl -s -o "$script_path" https://raw.githubusercontent.com/erfjab/ESSL/master/essl.sh
    chmod +x "$script_path"
    success "RSSL script installed successfully."
}

# Function to upgrade the RSSL script
upgrade_script() {
    log "Upgrading RSSL script..."
    local install_dir="/usr/local/bin"
    local script_path="$install_dir/rssl"

    if [ -f "$script_path" ]; then
        curl -s -o "$script_path" https://raw.githubusercontent.com/erfjab/ESSL/master/essl.sh
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
        success "RSSL script removed successfully."
    else
        warn "RSSL script is not installed in /usr/local/bin/rssl"
    fi
}

# Function to display help message
show_help() {
    cat << EOF
    
Usage: rssl [email] [domain1 domain2 ...] <destination> | --install | --upgrade | --uninstall

Email:
  Provide an email address to use with acme.sh and certbot.

Domains:
  You can provide one or more domains.

Destination:
  Use 'marzban', 'marzneshin', 'x-ui', '3x-ui', 'rebecca', 'pasarguard', 's-ui', 'ovpanel' or 'hiddify' for predefined paths,
  or provide a custom path starting with '/'.

Commands:
  --install     Install the RSSL script.
  --upgrade     Upgrade the RSSL script to the latest version.
  --uninstall   Uninstall the RSSL script from the system.
  --help        Show this help message.
  --version     Show script version

Examples:
  rssl user@example.com example.com /etc/ssl/certs
  rssl user@example.com domain1.com domain2.com domain3.com /custom/path
  rssl --install
  rssl --upgrade

Note: This script must be run as root.

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
    echo -e "  7) Custom Path (e.g., /etc/ssl/certs)"
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
            echo -ne "${orange}Enter your custom absolute path (must start with /): ${reset}"
            read -r target_panel
            ;;
        *)
            error "Invalid choice."
            exit 1
            ;;
    esac

    echo -ne "${orange}Enter your Email (for SSL registration): ${reset}"
    read -r email
    if [[ -z "$email" ]]; then
        error "Email cannot be empty."
        exit 1
    fi

    echo -ne "${orange}Enter your Domain or Subdomain (for multiple domains, separate with space): ${reset}"
    read -r -a domains
    if [ ${#domains[@]} -eq 0 ]; then
        error "You must enter at least one domain."
        exit 1
    fi

    # Trigger the core installation logic using the interactive inputs
    issue_ssl_process "$email" "$target_panel" "${domains[@]}"
}

# Core logic function to issue SSL separated from main arguments
issue_ssl_process() {
    local email="$1"
    local destination="$2"
    shift 2
    local domains=("$@")

    # Validate and handle the domains
    for domain in "${domains[@]}"; do
        validate_domain "$domain" || exit 1
    done

    # Set predefined paths if necessary
    case "$destination" in
        marzban) base_destination="/var/lib/marzban/certs" ;;
        marzneshin) base_destination="/var/lib/marzneshin/certs" ;;
        ovpanel) base_destination="/opt/ov-panel/data" ;;
        x-ui|3x-ui|s-ui|hiddify) base_destination="/certs" ;;
        pasarguard) base_destination="/var/lib/pasarguard/certs" ;;
        rebecca) base_destination="/var/lib/rebecca/certs" ;;
        *)
            if [[ "$destination" != /* ]]; then
                error "Invalid destination path. Must start with '/'"
                exit 1
            fi
            base_destination="$destination"
            ;;
    esac
    [[ "$destination" != */ ]] && destination="${destination}/"

    # Install dependencies
    install_dependencies

    # Create subdirectory using the first domain
    first_domain="${domains[0]}"
    destination="${base_destination}/${first_domain}/"

    # Try acme.sh first
    if get_install_certificate_acme "${domains[@]}"; then
        log "Certificate successfully obtained using acme.sh"
    else
        warn "Failed to obtain certificate using acme.sh. Trying certbot..."
        if get_install_certificate_certbot "${domains[@]}"; then
            log "Certificate successfully obtained using certbot"
        else
            error "Failed to obtain certificate using both acme.sh and certbot"
            exit 1
        fi
    fi

    # Display final certificate path
    success "Certificate files are located at:"
    print "⭐ Private key: ${destination}privkey.pem"
    print "⭐ Full chain: ${destination}fullchain.pem"
}

# Interactive menu function
show_interactive_menu() {
    print "Please choose an option:"
    echo -e "${spring}1)${reset} Install RSSL Script"
    echo -e "${spring}2)${reset} Uninstall RSSL Script"
    echo -e "${spring}3)${reset} Get SSL Certificate (Interactive)"
    echo -e "${spring}4)${reset} Show Help Manual"
    echo -e "${spring}5)${reset} Exit"
    echo -ne "${orange}Enter choice [1-5]: ${reset}"
    read -r choice

    case "$choice" in
        1)
            install_script
            exit 0
            ;;
        2)
            uninstall_script
            exit 0
            ;;
        3)
            interactive_ssl
            exit 0
            ;;
        4)
            show_help
            exit 0
            ;;
        5)
            print "Exiting..."
            exit 0
            ;;
        *)
            error "Invalid option."
            exit 1
            ;;
    esac
}

# Main function to handle the script logic
main() {
    [ "$EUID" -eq 0 ] || { error "This script must be run as root."; exit 1; }

    # Handle --install, --upgrade, and --uninstall options
    case "$1" in
        --install)
            install_script
            exit 0
            ;;
        --upgrade)
            upgrade_script
            exit 0
            ;;
        --uninstall)
            uninstall_script
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            print "currect rssl version: v3.1.2"
            exit 0
            ;;
    esac

    # Check if user provided enough arguments for CLI SSL installation
    if [ $# -lt 3 ]; then
        error "Not enough arguments provided. Use 'rssl --help' for more details."
        exit 1
    fi

    # CLI mode flow
    local email_cli="$1"
    shift
    local dest_cli="${@: -1}"
    local domains_cli=("${@:1:$#-1}")
    
    issue_ssl_process "$email_cli" "$dest_cli" "${domains_cli[@]}"
}

# When executing without arguments, display banner and interactive menu
if [ $# -eq 0 ]; then
    show_banner
    show_interactive_menu
else
    show_banner
    main "$@"
fi
