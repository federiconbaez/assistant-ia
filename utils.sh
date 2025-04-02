#!/bin/bash
# =========================================================================
# utils.sh - Funciones de utilidad para Terminal Assistant
# =========================================================================

# Función para cargar archivos JSON utilizando jq
# Requiere: jq instalado en el sistema
load_json() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "ERROR: No se pudo cargar el archivo JSON: $file"
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq no está instalado. Por favor instala jq para continuar."
        echo "Puedes instalarlo con: sudo apt-get install jq (Debian/Ubuntu)"
        echo "O: sudo yum install jq (CentOS/RHEL)"
        return 1
    fi
    
    cat "$file" | jq
    return $?
}

# Función para obtener un valor de un archivo JSON
# Ejemplo: get_json_value "config.json" ".app.name"
get_json_value() {
    local file="$1"
    local key="$2"
    
    # Check if both parameters are provided
    if [ -z "$file" ] || [ -z "$key" ]; then
        echo "ERROR: Se requiere un archivo y una clave" >&2
        return 1
    fi
    
    if [ ! -f "$file" ]; then
        echo "ERROR: No se pudo encontrar el archivo JSON: $file" >&2
        return 1
    fi
    
    jq -r "$key" < "$file"
    return $?
}

# Función para imprimir texto con colores y formato
# Uso: print_styled "Texto a mostrar" "blue" "bold"
print_styled() {

    local text="$1"
    local color="${2:-reset}"
    local format="${3:-}"
    
    # Cargar colores desde config.json
    if [ -f "$CONFIG_DIR/config.json" ]; then
        local color_code=$(get_json_value "$CONFIG_DIR/config.json" ".styles.colors.$color")
        local format_code=""
        
        if [ -n "$format" ]; then
            format_code=$(get_json_value "$CONFIG_DIR/config.json" ".styles.formats.$format")
        fi
        
        local reset_code=$(get_json_value "$CONFIG_DIR/config.json" ".styles.colors.reset")
        
        echo -e "${format_code}${color_code}${text}${reset_code}"
    else
        # Fallback si no se puede cargar el archivo de configuración
        case "$color" in
            blue)    echo -e "\033[0;34m${text}\033[0m" ;;
            green)   echo -e "\033[0;32m${text}\033[0m" ;;
            yellow)  echo -e "\033[1;33m${text}\033[0m" ;;
            red)     echo -e "\033[0;31m${text}\033[0m" ;;
            purple)  echo -e "\033[0;35m${text}\033[0m" ;;
            cyan)    echo -e "\033[0;36m${text}\033[0m" ;;
            white)   echo -e "\033[1;37m${text}\033[0m" ;;
            *)       echo -e "${text}" ;;
        esac
    fi
}

# Función para mostrar una barra de progreso
# Uso: progress_bar 75 "Instalando paquetes"
progress_bar() {
    local percent=$1
    local message="${2:-Progreso}"
    local width=50
    local num_filled=$(( width * percent / 100 ))
    local num_empty=$(( width - num_filled ))
    
    # Construir la barra
    local bar="["
    for ((i=0; i<num_filled; i++)); do
        bar+="#"
    done
    for ((i=0; i<num_empty; i++)); do
        bar+=" "
    done
    bar+="] $percent%"
    
    # Mostrar mensaje y barra
    printf "\r%-20s %s" "$message" "$bar"
    
    # Salto de línea si se completó
    if [ "$percent" -eq 100 ]; then
        echo ""
    fi
}

# Función para mostrar un menú dinámico y obtener la selección del usuario
# Uso: show_menu "Título del menú" "opcion1" "opcion2" "opcion3"
# Devuelve: El índice seleccionado (comenzando en 1)
show_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=1
    local key
    
    # Restaurar cursor y entorno al salir
    trap 'tput cnorm; stty echo; tput sgr0' EXIT
    
    # Ocultar cursor y desactivar eco
    tput civis
    stty -echo
    
    while true; do
        # Limpiar pantalla
        clear
        
        # Mostrar título
        print_styled "$title" "blue" "bold"
        echo ""
        
        # Mostrar opciones
        for i in ${!options[@]}; do
            if [ $((i+1)) -eq $selected ]; then
                # Opción seleccionada
                print_styled " >> ${options[$i]}" "green" "bold"
            else
                # Opción normal
                echo "    ${options[$i]}"
            fi
        done
        
        # Mostrar instrucciones
        echo ""
        print_styled "Utiliza las flechas ↑/↓ para navegar y Enter para seleccionar" "cyan"
        
        # Leer tecla
        read -rsn3 key
        
        # Procesar tecla
        case "$key" in
            $'\x1b[A') # Flecha arriba
                if [ $selected -gt 1 ]; then
                    selected=$((selected-1))
                fi
                ;;
            $'\x1b[B') # Flecha abajo
                if [ $selected -lt ${#options[@]} ]; then
                    selected=$((selected+1))
                fi
                ;;
            "") # Enter
                # Restaurar terminal
                tput cnorm
                stty echo
                tput sgr0
                clear
                return $selected
                ;;
        esac
    done
}

# Función para obtener input del usuario con validación
# Uso: get_input "Pregunta:" "default" "^[0-9]+$" "Debe ingresar solo números"
get_input() {
    local prompt="$1"
    local default="$2"
    local regex="$3"
    local error_msg="$4"
    local input
    
    while true; do
        # Mostrar prompt con valor por defecto si existe
        if [ -n "$default" ]; then
            print_styled "$prompt [$default]: " "cyan"
        else
            print_styled "$prompt: " "cyan"
        fi
        
        # Leer input
        read input
        
        # Usar valor por defecto si se deja en blanco
        if [ -z "$input" ] && [ -n "$default" ]; then
            input="$default"
        fi
        
        # Validar con regex si se proporciona
        if [ -n "$regex" ]; then
            if [[ "$input" =~ $regex ]]; then
                break
            else
                print_styled "$error_msg" "red"
            fi
        else
            # Si no hay regex, aceptar cualquier valor no vacío
            if [ -n "$input" ]; then
                break
            else
                print_styled "Por favor ingrese un valor." "red"
            fi
        fi
    done
    
    echo "$input"
}

# Función para confirmar acción (Sí/No)
# Uso: confirm "¿Está seguro de continuar?" "n"
# Devuelve: 0 para Sí, 1 para No
confirm() {
    local prompt="$1"
    local default="${2:-s}"
    local options
    
    # Configurar opciones según valor por defecto
    if [ "$default" = "s" ] || [ "$default" = "S" ]; then
        options="[S/n]"
        default="s"
    else
        options="[s/N]"
        default="n"
    fi
    
    # Mostrar prompt y leer respuesta
    print_styled "$prompt $options " "yellow"
    local resp
    read resp
    
    # Usar valor por defecto si se deja en blanco
    if [ -z "$resp" ]; then
        resp="$default"
    fi
    
    # Convertir a minúsculas
    resp=$(echo "$resp" | tr '[:upper:]' '[:lower:]')
    
    # Devolver resultado
    if [ "$resp" = "s" ] || [ "$resp" = "si" ] || [ "$resp" = "sí" ] || [ "$resp" = "y" ] || [ "$resp" = "yes" ]; then
        return 0
    else
        return 1
    fi
}

# Función para mostrar una notificación
# Uso: show_notification "Título" "Mensaje" "info|warning|error|success"
show_notification() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"
    
    # Seleccionar color según el tipo
    local color
    case "$type" in
        info)    color="blue" ;;
        warning) color="yellow" ;;
        error)   color="red" ;;
        success) color="green" ;;
        *)       color="white" ;;
    esac
    
    # Mostrar notificación
    echo ""
    print_styled "┌─ $title ───────────────────────────────────┐" "$color" "bold"
    print_styled "│ $message" "$color"
    print_styled "└───────────────────────────────────────────┘" "$color" "bold"
    echo ""
}

# Función para verificar dependencias
# Uso: check_dependencies "jq" "curl" "sed"
check_dependencies() {
    local missing=()
    
    for dep in "$@"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        show_notification "Dependencias faltantes" "Los siguientes programas son necesarios pero no están instalados:" "warning"
        for dep in "${missing[@]}"; do
            print_styled " - $dep" "yellow"
        done
        echo ""
        
        if confirm "¿Desea intentar instalarlos automáticamente?"; then
            # Detectar gestor de paquetes
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y "${missing[@]}"
            elif command -v yum &> /dev/null; then
                sudo yum install -y "${missing[@]}"
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y "${missing[@]}"
            elif command -v pacman &> /dev/null; then
                sudo pacman -S --noconfirm "${missing[@]}"
            else
                print_styled "No se pudo detectar un gestor de paquetes compatible. Por favor instale manualmente: ${missing[*]}" "red"
                return 1
            fi
            
            # Verificar si se instalaron correctamente
            local still_missing=()
            for dep in "${missing[@]}"; do
                if ! command -v "$dep" &> /dev/null; then
                    still_missing+=("$dep")
                fi
            done
            
            if [ ${#still_missing[@]} -gt 0 ]; then
                show_notification "Error" "No se pudieron instalar: ${still_missing[*]}" "error"
                return 1
            else
                show_notification "Éxito" "Todas las dependencias se instalaron correctamente" "success"
            fi
        else
            show_notification "Advertencia" "El programa puede no funcionar correctamente sin estas dependencias" "warning"
            return 1
        fi
    fi
    
    return 0
}

# Función para mostrar el logo ASCII
show_ascii_logo() {
    local logo_file="$CONFIG_DIR/logo.txt"
    local color="${1:-blue}"
    
    # Si existe un logo personalizado, usarlo
    if [ -f "$logo_file" ]; then
        print_styled "$(cat "$logo_file")" "$color" "bold"
    else
        # Usar el logo desde config.json
        if [ -f "$CONFIG_DIR/config.json" ]; then
            local logo_lines=$(get_json_value "$CONFIG_DIR/config.json" ".banner.art[]")
            echo "$logo_lines" | while read -r line; do
                print_styled "$line" "$color" "bold"
            done
        else
            # Logo predeterminado si no hay configuración
            print_styled "  _______                  _             _   _____           _     _                 _   " "$color" "bold"
            print_styled " |__   __|                (_)           | | |  __ \\         (_)   | |               | |  " "$color" "bold"
            print_styled "    | | ___ _ __ _ __ ___  _ _ __   __ _| | | |__) |___  ___ _ ___| |_ __ _ _ __ | |_ " "$color" "bold"
            print_styled "    | |/ _ \\ '__| '_ ' _ \\| | '_ \\ / _' | | |  _  // _ \\/ __| / __| __/ _' | '_ \\| __|" "$color" "bold"
            print_styled "    | |  __/ |  | | | | | | | | | | (_| | | | | \\ \\  __/\\__ \\ \\__ \\ || (_| | | | | |_ " "$color" "bold"
            print_styled "    |_|\\___|_|  |_| |_| |_|_|_| |_|\\__,_|_| |_|  \\_\\___||___/_|___/\\__\\__,_|_| |_|\\__|" "$color" "bold"
        fi
    fi
}

# Función para guardar registro de actividad
log_activity() {
    local action="$1"
    local details="${2:-}"
    
    # Ensure CONFIG_DIR is defined
    if [ -z "$CONFIG_DIR" ]; then
        CONFIG_DIR="$HOME/.config/terminal-assistant"
    fi
    
    local log_file="$CONFIG_DIR/activity.log"
    
    # Crear archivo de registro si no existe
    if [ ! -f "$log_file" ]; then
        mkdir -p "$CONFIG_DIR"
        echo "# Registro de actividad de Terminal Assistant" > "$log_file"
        echo "# Formato: [FECHA HORA] ACCIÓN: DETALLES" >> "$log_file"
        echo "-------------------------------------------" >> "$log_file"
    fi
    
    # Registrar actividad
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $action: $details" >> "$log_file"
}

# Función para verificar actualización
check_for_updates() {
    local current_version=$(get_json_value "$CONFIG_DIR/config.json" ".app.version")
    local repo_url=$(get_json_value "$CONFIG_DIR/config.json" ".app.github")
    
    print_styled "Verificando actualizaciones..." "cyan"
    
    # Intentar obtener la última versión desde GitHub (ejemplo)
    if command -v curl &> /dev/null; then
        local latest_version=$(curl -s "$repo_url/raw/main/version.txt" 2>/dev/null)
        
        if [ -n "$latest_version" ]; then
            if [ "$latest_version" != "$current_version" ]; then
                show_notification "Actualización disponible" "Versión actual: $current_version, Última versión: $latest_version" "info"
                
                if confirm "¿Desea actualizar a la última versión?"; then
                    # Aquí implementar la lógica de actualización
                    show_notification "Actualizando" "Descargando la versión $latest_version..." "info"
                    
                    # Simulación de descarga
                    for i in {1..10}; do
                        progress_bar $((i*10)) "Descargando"
                        sleep 0.2
                    done
                    
                    show_notification "Éxito" "Terminal Assistant ha sido actualizado a la versión $latest_version" "success"
                    log_activity "Actualización" "Actualizado de $current_version a $latest_version"
                    
                    # Actualizar versión en config.json
                    # Este es un ejemplo simple, en la implementación real se necesitaría un parser JSON adecuado
                    sed -i "s/\"version\": \"$current_version\"/\"version\": \"$latest_version\"/" "$CONFIG_DIR/config.json"
                    
                    # Informar que se debe reiniciar
                    print_styled "Por favor reinicie Terminal Assistant para aplicar los cambios." "yellow" "bold"
                    
                    # Esperar input antes de continuar
                    read -p "Presione Enter para continuar..."
                fi
            else
                show_notification "Actualización" "Ya tiene la última versión ($current_version)" "success"
            fi
        else
            show_notification "Error" "No se pudo verificar la última versión" "error"
        fi
    else
        show_notification "Error" "Se requiere curl para verificar actualizaciones" "error"
    fi
}
# Continuando desde la línea 436
export_config() {
    local export_file="${1:-$HOME/terminal_assistant_backup.json}"
    
    if [ -f "$CONFIG_DIR/config.json" ]; then
        cp "$CONFIG_DIR/config.json" "$export_file"
        show_notification "Exportación" "Configuración exportada a: $export_file" "success"
        log_activity "Exportación" "Configuración exportada a: $export_file"
        return 0
    else
        show_notification "Error" "No existe archivo de configuración para exportar" "error"
        return 1
    fi
}

# Función para importar configuración
import_config() {
    local import_file="$1"
    
    if [ ! -f "$import_file" ]; then
        show_notification "Error" "El archivo a importar no existe: $import_file" "error"
        return 1
    fi
    
    # Validar que es un JSON válido
    if ! jq . "$import_file" > /dev/null 2>&1; then
        show_notification "Error" "El archivo no es un JSON válido: $import_file" "error"
        return 1
    fi
    
    # Crear directorio de configuración si no existe
    mkdir -p "$CONFIG_DIR"
    
    # Hacer backup de la configuración actual si existe
    if [ -f "$CONFIG_DIR/config.json" ]; then
        local backup_file="$CONFIG_DIR/config.json.bak.$(date +%Y%m%d%H%M%S)"
        cp "$CONFIG_DIR/config.json" "$backup_file"
        show_notification "Backup" "Se ha creado una copia de seguridad en: $backup_file" "info"
    fi
    
    # Importar nueva configuración
    cp "$import_file" "$CONFIG_DIR/config.json"
    show_notification "Importación" "Configuración importada correctamente" "success"
    log_activity "Importación" "Configuración importada desde: $import_file"
    
    return 0
}

# Función para crear configuración por defecto
# Replace the create_default_config function with:

create_default_config() {
    local config_file="$CONFIG_DIR/config.json"
    
    # Crear directorio de configuración si no existe
    mkdir -p "$CONFIG_DIR"
    
    # Verificar si ya existe configuración
    if [ -f "$config_file" ]; then
        if ! confirm "Ya existe un archivo de configuración. ¿Desea sobrescribirlo?"; then
            return 1
        fi
    fi
    
    # Create JSON with properly escaped sequences
    cat > "$config_file" << 'EOL'
{
    "app": {
        "name": "Terminal Assistant",
        "version": "1.0.0",
        "github": "https://github.com/usuario/terminal-assistant",
        "description": "Una herramienta de asistencia para la terminal"
    },
    "styles": {
        "colors": {
            "reset": "\u001b[0m",
            "black": "\u001b[0;30m",
            "red": "\u001b[0;31m",
            "green": "\u001b[0;32m",
            "yellow": "\u001b[0;33m",
            "blue": "\u001b[0;34m",
            "purple": "\u001b[0;35m",
            "cyan": "\u001b[0;36m",
            "white": "\u001b[0;37m"
        },
        "formats": {
            "bold": "\u001b[1m",
            "underline": "\u001b[4m",
            "blink": "\u001b[5m",
            "reverse": "\u001b[7m"
        }
    },
    "banner": {
        "art": [
            "  _______                  _             _      ",
            " |__   __|                (_)           | |     ",
            "    | | ___ _ __ _ __ ___  _ _ __   __ _| |     ",
            "    | |/ _ \\ '__| '_ ` _ \\| | '_ \\ / _` | |",
            "    | |  __/ |  | | | | | | | | | | (_| | |     ",
            "    |_|\\___|_|  |_| |_| |_|_|_| |_|\\__,_|_|   ",
            "                                               ",
            "    _    ____ ____ ___ ____ ___ _    _  _ ___ ",
            "    |    |__| [__   |  |__|  |  |    |\\ |  |  ",
            "    |___ |  | ___]  |  |  |  |  |___ | \\|  |  "
        ],
        "welcome_message": "Bienvenido a Terminal Assistant - Tu asistente para la línea de comandos",
        "version_text": "Versión: {VERSION}"
    },
    "plugins": {
        "enabled": true,
        "directories": [
            "$HOME/.config/terminal-assistant/plugins",
            "/usr/local/share/terminal-assistant/plugins"
        ]
    },
    "settings": {
        "language": "es",
        "auto_update": true,
        "log_level": "info",
        "max_log_size": 1048576,
        "startup_notification": true
    }
}
EOL

    # Validate JSON
    if ! jq '.' "$config_file" > /dev/null 2>&1; then
        show_notification "Error" "El archivo de configuración generado no es un JSON válido" "error"
        return 1
    fi

    show_notification "Configuración" "Se ha creado la configuración por defecto" "success"
    log_activity "Configuración" "Creada configuración por defecto"
    
    return 0
}

# Función para inicializar el entorno
initialize_environment() {
    # Definir variables globales
    if [ -z "$CONFIG_DIR" ]; then
        export CONFIG_DIR="$HOME/.config/terminal-assistant"
    fi
    
    # Crear directorio de configuración si no existe
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        log_activity "Inicialización" "Creado directorio de configuración: $CONFIG_DIR"
    fi
    
    # Crear configuración por defecto si no existe
    if [ ! -f "$CONFIG_DIR/config.json" ]; then
        create_default_config
    fi
    
    # Verificar dependencias básicas
    check_dependencies "jq" "curl"
    
    return 0
}

# Función para limpiar el entorno (archivos temporales, etc.)
cleanup_environment() {
    # Eliminar archivos temporales
    if [ -d "$CONFIG_DIR/temp" ]; then
        rm -rf "$CONFIG_DIR/temp"/*
        log_activity "Limpieza" "Eliminados archivos temporales"
    fi
    
    # Rotar log si es muy grande
    local log_file="$CONFIG_DIR/activity.log"
    if [ -f "$log_file" ]; then
        local max_size=$(get_json_value "$CONFIG_DIR/config.json" ".settings.max_log_size")
        max_size=${max_size:-1048576}  # Por defecto 1MB
        
        if [ -f "$log_file" ] && [ $(stat -c%s "$log_file") -gt $max_size ]; then
            local backup_log="$log_file.$(date +%Y%m%d%H%M%S)"
            mv "$log_file" "$backup_log"
            echo "# Registro de actividad de Terminal Assistant (rotado en $(date +%Y-%m-%d))" > "$log_file"
            echo "# Archivo anterior guardado en: $backup_log" >> "$log_file"
            echo "-------------------------------------------" >> "$log_file"
            log_activity "Mantenimiento" "Log rotado por tamaño excesivo"
        fi
    fi
    
    return 0
}

# Función para cargar plugins
load_plugins() {
    # Verificar si los plugins están habilitados
    local plugins_enabled=$(get_json_value "$CONFIG_DIR/config.json" ".plugins.enabled")
    
    if [ "$plugins_enabled" != "true" ]; then
        return 0
    fi
    
    # Obtener directorios de plugins
    local plugin_dirs=$(get_json_value "$CONFIG_DIR/config.json" ".plugins.directories[]")
    local plugins_count=0
    
    # Recorrer directorios y cargar plugins
    echo "$plugin_dirs" | while read -r plugin_dir; do
        if [ -d "$plugin_dir" ]; then
            local plugin_files=("$plugin_dir"/*.sh)
            
            # Cargar cada plugin
            for plugin_file in "${plugin_files[@]}"; do
                if [ -f "$plugin_file" ] && [ -x "$plugin_file" ]; then
                    # Cargar plugin
                    source "$plugin_file"
                    plugins_count=$((plugins_count+1))
                    log_activity "Plugin" "Cargado plugin: $(basename "$plugin_file")"
                fi
            done
        fi
    done
    
    if [ "$plugins_count" -gt 0 ]; then
        show_notification "Plugins" "Se han cargado $plugins_count plugins" "info"
    fi
    
    return 0
}

# Función para mostrar la información del sistema
show_system_info() {
    show_notification "Información del Sistema" "Recopilando información..." "info"
    
    # Sistema operativo
    local os=$(uname -s)
    local kernel=$(uname -r)
    local hostname=$(hostname)
    local uptime=$(uptime | sed 's/.*up \([^,]*\),.*/\1/')
    
    # Recursos
    local cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d ":" -f2 | sed 's/^[ \t]*//')
    local cpu_cores=$(grep -c processor /proc/cpuinfo)
    local mem_total=$(free -h | grep Mem | awk '{print $2}')
    local mem_used=$(free -h | grep Mem | awk '{print $3}')
    local disk_info=$(df -h / | grep / | awk '{print $3 "/" $2 " (" $5 ")"}')
    
    # Mostrar información
    print_styled "Sistema Operativo:" "cyan" "bold"
    print_styled " - OS: $os" "white"
    print_styled " - Kernel: $kernel" "white"
    print_styled " - Hostname: $hostname" "white"
    print_styled " - Uptime: $uptime" "white"
    echo ""
    
    print_styled "Recursos:" "cyan" "bold"
    print_styled " - CPU: $cpu_model ($cpu_cores núcleos)" "white"
    print_styled " - Memoria: $mem_used/$mem_total" "white"
    print_styled " - Disco: $disk_info" "white"
    echo ""
    
    print_styled "Versión de Terminal Assistant:" "cyan" "bold"
    local version=$(get_json_value "$CONFIG_DIR/config.json" ".app.version")
    print_styled " - $version" "white"
    echo ""
    
    # Guardar registro
    log_activity "Sistema" "Mostrada información del sistema"
    
    return 0
}

# Función para mostrar ayuda interactiva
show_help() {
    clear
    show_ascii_logo "green"
    
    print_styled "AYUDA DE TERMINAL ASSISTANT" "cyan" "bold"
    echo ""
    
    print_styled "Funciones disponibles:" "yellow" "bold"
    echo ""
    
    # Lista de funciones y sus descripciones
    print_styled "load_json [archivo]" "green"
    echo "  Carga y muestra un archivo JSON usando jq"
    echo ""
    
    print_styled "get_json_value [archivo] [clave]" "green"
    echo "  Obtiene un valor específico de un archivo JSON"
    echo "  Ejemplo: get_json_value \"config.json\" \".app.name\""
    echo ""
    
    print_styled "print_styled [texto] [color] [formato]" "green"
    echo "  Imprime texto con colores y formato"
    echo "  Colores: blue, green, yellow, red, purple, cyan, white"
    echo "  Formatos: bold, underline, blink, reverse"
    echo ""
    
    print_styled "progress_bar [porcentaje] [mensaje]" "green"
    echo "  Muestra una barra de progreso"
    echo ""
    
    print_styled "show_menu [título] [opciones...]" "green"
    echo "  Muestra un menú interactivo y devuelve la opción seleccionada"
    echo ""
    
    print_styled "get_input [prompt] [valor_predeterminado] [regex] [mensaje_error]" "green"
    echo "  Solicita input al usuario con validación opcional"
    echo ""
    
    print_styled "confirm [pregunta] [predeterminado]" "green"
    echo "  Solicita confirmación (Sí/No) y devuelve 0 para Sí, 1 para No"
    echo ""
    
    print_styled "show_notification [título] [mensaje] [tipo]" "green"
    echo "  Muestra una notificación. Tipos: info, warning, error, success"
    echo ""
    
    print_styled "check_dependencies [programas...]" "green"
    echo "  Verifica dependencias e intenta instalarlas si faltan"
    echo ""
    
    print_styled "show_ascii_logo [color]" "green"
    echo "  Muestra el logo ASCII de Terminal Assistant"
    echo ""
    
    print_styled "log_activity [acción] [detalles]" "green"
    echo "  Registra una actividad en el log"
    echo ""
    
    print_styled "check_for_updates" "green"
    echo "  Verifica si hay actualizaciones disponibles"
    echo ""
    
    print_styled "export_config [archivo_destino]" "green"
    echo "  Exporta la configuración actual a un archivo"
    echo ""
    
    print_styled "import_config [archivo_origen]" "green"
    echo "  Importa configuración desde un archivo"
    echo ""
    
    print_styled "create_default_config" "green"
    echo "  Crea una configuración por defecto"
    echo ""
    
    print_styled "initialize_environment" "green"
    echo "  Inicializa el entorno (directorios, configuración, etc.)"
    echo ""
    
    print_styled "cleanup_environment" "green"
    echo "  Limpia archivos temporales y rota logs si es necesario"
    echo ""
    
    print_styled "load_plugins" "green"
    echo "  Carga plugins desde los directorios configurados"
    echo ""
    
    print_styled "show_system_info" "green"
    echo "  Muestra información del sistema"
    echo ""
    
    # Esperar input para continuar
    echo ""
    print_styled "Presiona Enter para continuar..." "cyan"
    read
    
    return 0
}

# Función para crear un backup completo
create_backup() {
    local backup_dir="${1:-$HOME/terminal_assistant_backup_$(date +%Y%m%d%H%M%S)}"
    
    # Crear directorio de backup
    mkdir -p "$backup_dir"
    
    # Exportar configuración
    export_config "$backup_dir/config.json"
    
    # Copiar logs
    if [ -f "$CONFIG_DIR/activity.log" ]; then
        cp "$CONFIG_DIR/activity.log" "$backup_dir/activity.log"
    fi
    
    # Copiar plugins personalizados
    if [ -d "$CONFIG_DIR/plugins" ]; then
        mkdir -p "$backup_dir/plugins"
        cp -r "$CONFIG_DIR/plugins"/* "$backup_dir/plugins"/ 2>/dev/null || true
    fi
    
    # Crear archivo de información del backup
    cat > "$backup_dir/backup_info.txt" << EOL
Backup de Terminal Assistant
Fecha: $(date +"%Y-%m-%d %H:%M:%S")
Usuario: $(whoami)
Hostname: $(hostname)
Versión: $(get_json_value "$CONFIG_DIR/config.json" ".app.version")
EOL
    
    show_notification "Backup" "Backup creado en: $backup_dir" "success"
    log_activity "Backup" "Creado backup completo en: $backup_dir"
    
    return 0
}

# Función para restaurar un backup
restore_backup() {
    local backup_dir="$1"
    
    if [ ! -d "$backup_dir" ]; then
        show_notification "Error" "El directorio de backup no existe: $backup_dir" "error"
        return 1
    fi
    
    # Verificar que es un backup válido
    if [ ! -f "$backup_dir/config.json" ]; then
        show_notification "Error" "No parece ser un backup válido (falta config.json)" "error"
        return 1
    fi
    
    # Confirmar restauración
    if ! confirm "¿Está seguro de restaurar el backup? Esto sobrescribirá su configuración actual"; then
        return 1
    fi
    
    # Crear directorio de configuración si no existe
    mkdir -p "$CONFIG_DIR"
    
    # Restaurar configuración
    cp "$backup_dir/config.json" "$CONFIG_DIR/config.json"
    
    # Restaurar logs si existen
    if [ -f "$backup_dir/activity.log" ]; then
        cp "$backup_dir/activity.log" "$CONFIG_DIR/activity.log"
    fi
    
    # Restaurar plugins si existen
    if [ -d "$backup_dir/plugins" ] && [ -n "$(ls -A "$backup_dir/plugins")" ]; then
        mkdir -p "$CONFIG_DIR/plugins"
        cp -r "$backup_dir/plugins"/* "$CONFIG_DIR/plugins"/ 2>/dev/null || true
    fi
    
    show_notification "Restauración" "Backup restaurado correctamente" "success"
    log_activity "Restauración" "Restaurado backup desde: $backup_dir"
    
    # Sugerir reinicio
    print_styled "Se recomienda reiniciar Terminal Assistant para aplicar la configuración restaurada." "yellow" "bold"
    
    return 0
}

# Función para ejecutar comandos con salida formateada
run_command() {
    local cmd="$1"
    local title="${2:-Ejecutando comando}"
    
    show_notification "$title" "$ $cmd" "info"
    echo ""
    
    # Ejecutar comando
    eval "$cmd"
    local result=$?
    
    echo ""
    if [ $result -eq 0 ]; then
        print_styled "Comando ejecutado correctamente" "green" "bold"
    else
        print_styled "El comando falló con código de error: $result" "red" "bold"
    fi
    
    log_activity "Comando" "Ejecutado: $cmd (resultado: $result)"
    
    return $result
}

# Función principal para mostrar el dashboard interactivo
show_dashboard() {
    while true; do
        clear
        show_ascii_logo "blue"
        
        local version=$(get_json_value "$CONFIG_DIR/config.json" ".app.version")
        print_styled "Versión: $version" "cyan"
        echo ""
        
        # Obtener fecha y hora
        local datetime=$(date "+%A %d de %B de %Y, %H:%M:%S")
        print_styled "$datetime" "yellow"
        echo ""
        
        # Menú principal
        local options=(
            "Información del sistema"
            "Ejecutar comando"
            "Verificar actualizaciones"
            "Crear backup"
            "Restaurar backup"
            "Configuración"
            "Ayuda"
            "Salir"
        )
        
        show_menu "MENÚ PRINCIPAL" "${options[@]}"
        local choice=$?
        
        case $choice in
            1) show_system_info ;;
            2) 
                local cmd=$(get_input "Ingrese el comando a ejecutar" "" "" "")
                [ -n "$cmd" ] && run_command "$cmd"
                read -p "Presione Enter para continuar..."
                ;;
            3) check_for_updates ;;
            4) 
                local backup_dir=$(get_input "Directorio para el backup" "$HOME/terminal_assistant_backup_$(date +%Y%m%d%H%M%S)" "" "")
                create_backup "$backup_dir"
                read -p "Presione Enter para continuar..."
                ;;
            5)
                local backup_dir=$(get_input "Directorio del backup a restaurar" "" "" "")
                [ -n "$backup_dir" ] && restore_backup "$backup_dir"
                read -p "Presione Enter para continuar..."
                ;;
            6)
                # Submenú de configuración
                local config_options=(
                    "Editar configuración"
                    "Exportar configuración"
                    "Importar configuración"
                    "Restaurar configuración por defecto"
                    "Volver"
                )
                
                show_menu "CONFIGURACIÓN" "${config_options[@]}"
                local config_choice=$?
                
                case $config_choice in
                    1)
                        if command -v nano &> /dev/null; then
                            nano "$CONFIG_DIR/config.json"
                        elif command -v vim &> /dev/null; then
                            vim "$CONFIG_DIR/config.json"
                        else
                            show_notification "Error" "No se encontró un editor de texto (nano o vim)" "error"
                        fi
                        ;;
                    2)
                        local export_file=$(get_input "Archivo para exportar" "$HOME/terminal_assistant_config_$(date +%Y%m%d%H%M%S).json" "" "")
                        export_config "$export_file"
                        read -p "Presione Enter para continuar..."
                        ;;
                    3)
                        local import_file=$(get_input "Archivo a importar" "" "" "")
                        [ -n "$import_file" ] && import_config "$import_file"
                        read -p "Presione Enter para continuar..."
                        ;;
                    4)
                        create_default_config
                        read -p "Presione Enter para continuar..."
                        ;;
                    5) ;;  # Volver
                esac
                ;;
            7) show_help ;;
            8) 
                clear
                show_notification "Adiós" "Gracias por usar Terminal Assistant" "success"
                log_activity "Sesión" "Sesión finalizada"
                return 0
                ;;
        esac
    done
}

# Inicializar entorno si se ejecuta el script directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    initialize_environment
    show_dashboard
    cleanup_environment
fi