#!/bin/bash

# Скрипт для установки Pelican Wings на Linux
# Поддерживаемые дистрибутивы: Ubuntu/Debian, CentOS/RHEL/Rocky/AlmaLinux

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для вывода цветного текста
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав суперпользователя
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться от имени root"
        print_status "Используйте: sudo $0"
        exit 1
    fi
}

# Определение дистрибутива
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        print_error "Не удалось определить дистрибутив Linux"
        exit 1
    fi
    
    print_status "Обнаружен дистрибутив: $DISTRO $VERSION"
}

# Установка зависимостей для Ubuntu/Debian
install_deps_debian() {
    print_status "Обновление списка пакетов..."
    apt update
    
    print_status "Установка зависимостей..."
    apt install -y curl tar unzip git redis-server
    
    # Установка Docker
    if ! command -v docker &> /dev/null; then
        print_status "Установка Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        print_success "Docker уже установлен"
    fi
}

# Установка зависимостей для CentOS/RHEL/Rocky/AlmaLinux
install_deps_rhel() {
    print_status "Обновление списка пакетов..."
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
    
    $PKG_MANAGER update -y
    
    print_status "Установка зависимостей..."
    $PKG_MANAGER install -y curl tar unzip git redis
    
    # Установка Docker
    if ! command -v docker &> /dev/null; then
        print_status "Установка Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        print_success "Docker уже установлен"
    fi
    
    # Запуск и включение Redis
    systemctl enable redis
    systemctl start redis
}

# Создание пользователя для Wings
create_wings_user() {
    if ! id "pelican" &>/dev/null; then
        print_status "Создание пользователя pelican..."
        useradd -r -d /etc/pelican -s /bin/bash pelican
        mkdir -p /etc/pelican
        chown pelican:pelican /etc/pelican
    else
        print_success "Пользователь pelican уже существует"
    fi
}

# Скачивание и установка Wings
install_wings() {
    print_status "Скачивание последней версии Pelican Wings..."
    
    # Получение последней версии с GitHub
    LATEST_VERSION=$(curl -s https://api.github.com/repos/pelican-dev/wings/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$LATEST_VERSION" ]]; then
        print_error "Не удалось получить информацию о последней версии"
        exit 1
    fi
    
    print_status "Последняя версия: $LATEST_VERSION"
    
    # Скачивание Wings
    DOWNLOAD_URL="https://github.com/pelican-dev/wings/releases/download/$LATEST_VERSION/wings_linux_amd64"
    
    curl -L -o /usr/local/bin/wings "$DOWNLOAD_URL"
    chmod +x /usr/local/bin/wings
    
    print_success "Wings установлен в /usr/local/bin/wings"
}

# Создание systemd сервиса
create_systemd_service() {
    print_status "Создание systemd сервиса..."
    
    cat > /etc/systemd/system/wings.service << 'EOF'
[Unit]
Description=Pelican Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wings
    
    print_success "Systemd сервис создан и включен"
}

# Настройка конфигурации
setup_config() {
    print_status "Настройка конфигурации Wings..."
    
    if [[ ! -f /etc/pelican/config.yml ]]; then
        print_warning "Файл конфигурации не найден"
        print_status "Создание базового файла конфигурации..."
        
        cat > /etc/pelican/config.yml << 'EOF'
debug: false
uuid: "CHANGEME"
token_id: "CHANGEME"
token: "CHANGEME"
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: false
    cert: ""
    key: ""
  upload_limit: 100
system:
  data: /var/lib/pelican/volumes
  sftp:
    bind_port: 2022
allowed_mounts: []
allowed_origins: []
EOF
        
        chown pelican:pelican /etc/pelican/config.yml
        chmod 600 /etc/pelican/config.yml
        
        print_warning "ВАЖНО: Необходимо отредактировать /etc/pelican/config.yml"
        print_warning "Укажите правильные значения для uuid, token_id и token из панели Pelican"
    else
        print_success "Файл конфигурации уже существует"
    fi
}

# Создание директорий
create_directories() {
    print_status "Создание необходимых директорий..."
    
    mkdir -p /var/lib/pelican/volumes
    mkdir -p /var/log/pelican
    mkdir -p /tmp/pelican
    mkdir -p /etc/pelican
    
    chown -R pelican:pelican /var/lib/pelican
    chown -R pelican:pelican /var/log/pelican
    chown -R pelican:pelican /tmp/pelican
    chown -R pelican:pelican /etc/pelican
    
    print_success "Директории созданы"
}

# Настройка брандмауэра
setup_firewall() {
    print_status "Настройка брандмауэра..."
    
    if command -v ufw &> /dev/null; then
        print_status "Настройка UFW..."
        ufw allow 8080/tcp
        ufw allow 2022/tcp
        ufw allow 25565:25665/tcp
        ufw allow 25565:25665/udp
        print_success "Правила UFW добавлены"
    elif command -v firewall-cmd &> /dev/null; then
        print_status "Настройка firewalld..."
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --permanent --add-port=2022/tcp
        firewall-cmd --permanent --add-port=25565-25665/tcp
        firewall-cmd --permanent --add-port=25565-25665/udp
        firewall-cmd --reload
        print_success "Правила firewalld добавлены"
    else
        print_warning "Брандмауэр не обнаружен. Убедитесь, что порты 8080 и 2022 открыты"
    fi
}

# Основная функция
main() {
    echo "========================================="
    echo "    Установщик Pelican Wings"
    echo "========================================="
    echo
    
    check_root
    detect_distro
    
    case $DISTRO in
        ubuntu|debian)
            install_deps_debian
            ;;
        centos|rhel|rocky|almalinux)
            install_deps_rhel
            ;;
        *)
            print_warning "Неподдерживаемый дистрибутив: $DISTRO"
            print_status "Попытка установки зависимостей..."
            ;;
    esac
    
    create_wings_user
    create_directories
    install_wings
    create_systemd_service
    setup_config
    setup_firewall
    
    echo
    echo "========================================="
    print_success "Установка Pelican Wings завершена!"
    echo "========================================="
    echo
    print_warning "СЛЕДУЮЩИЕ ШАГИ:"
    echo "1. Отредактируйте конфигурацию: nano /etc/pelican/config.yml"
    echo "2. Укажите правильные значения uuid, token_id и token из панели Pelican"
    echo "3. Запустите Wings: systemctl start wings"
    echo "4. Проверьте статус: systemctl status wings"
    echo "5. Просмотрите логи: journalctl -u wings -f"
    echo
    print_status "Для автозапуска: systemctl enable wings"
    print_status "Файл конфигурации: /etc/pelican/config.yml"
    print_status "Логи: journalctl -u wings"
}

# Запуск основной функции
main "$@"
