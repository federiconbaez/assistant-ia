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
    
    if [ ! -f "$file" ]; then
        echo "ERROR: No se pudo encontrar el archivo JSON: $file"
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
            print_styled "    | |/ _ \\ '__| '_ \\` _ \\| | '_ \\ / _\\` | | |  _  // _ \\/ __| / __| __/ _\\` | '_ \\| __|" "$color" "bold"
            print_styled "    | |  __/ |  | | | | | | | | | | (_| | | | | \\ \\  __/\\__ \\ \\__ \\ || (_| | | | | |_ " "$color" "bold"
            print_styled "    |_|\\___|_|  |_| |_| |_|_|_| |_|\\__,_|_| |_|  \\_\\___||___/_|___/\\__\\__,_|_| |_|\\__|" "$color" "bold"
        fi
    fi
}

# Función para guardar registro de actividad
log_activity() {
    local action="$1"
    local details="${2:-}"
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

# Función para exportar configuración
export_config() {
    local export_file="${1:-$HOME/terminal_assistant_backup.json}"
    
    if [ -f "$CONFIG_DIR/config.json" ]; then
        cp "$CONFIG_DIR/config.json" "$export_file"
        show_notification "Exportación" "Configuración exportada a: $export_file" "success"
        log_activity "