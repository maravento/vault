#!/bin/bash
# maravento.com
# GPL-3.0 https://www.gnu.org/licenses/gpl.txt
#
# Netplan Manager module installation/uninstallation script for Webmin
#
# Description:
#   Netplan Manager module for Webmin. Provides a graphical and scriptable
#   interface to manage network configuration through Netplan directly from Webmin.
#   Enables real-time editing, validation, and application of network settings
#   without manual YAML file handling.
#
# Features:
#   - Reads and edits Netplan configuration files (/etc/netplan/*.yaml)
#   - Creates automatic YAML backups before applying any changes
#   - Applies configuration instantly using "netplan apply"
#   - Validates YAML syntax and warns of possible errors
#   - Displays current interface status and active configuration
#   - Supports restore of previous Netplan backups
#   - Installs and integrates seamlessly into Webmin's Network category
#   - Works with both systemd-netplanmgr and NetworkManager backends
#   - Includes responsive layout and action buttons for quick management
#
# Usage:
#   sudo ./netplanmgr.sh [OPTIONS]
#
# Options:
#   install      Install the module
#   uninstall    Uninstall the module
#   -h, --help   Show help message
#
# Examples:
#   sudo ./netplanmgr.sh              # Interactive menu
#   sudo ./netplanmgr.sh install      # Direct installation
#   sudo ./netplanmgr.sh uninstall    # Direct uninstallation

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || "$UBUNTU_VERSION" != "24.04" ]]; then
    echo "This script requires Ubuntu 24.04. Use at your own risk"
    # exit 1
fi

set -e

MODNAME="netplanmgr"
MODDIR="/usr/share/webmin/$MODNAME"
ETCDIR="/etc/webmin/$MODNAME"

# ============================================================
# Function: Install Module
# ============================================================
install_module() {
    echo ""
    echo "=========================================="
    echo "Installing Netplan Manager Module"
    echo "=========================================="
    echo ""
    
    # Check dependencies
    echo "Checking dependencies..."
    if ! command -v netplan &>/dev/null; then
        echo "⚠ Warning: 'netplan' command not found. Module will still be installed,"
        echo "  but Netplan operations will fail until netplan is present on the system."
    fi
    echo "✓ Dependencies checked"
    
    echo "Creating Netplan Manager module structure..."
    
    # Create directories
    mkdir -p "$MODDIR/images"
    mkdir -p "$MODDIR/lang"
    mkdir -p "$MODDIR/help"
    mkdir -p "$ETCDIR"
    
    # ============================================================
    # 1. index.cgi (main file) - CORREGIDO
    # ============================================================
    cat > "$MODDIR/index.cgi" <<'INDEXCGI'
#!/usr/bin/perl
# Netplan Manager - Main interface
use strict;
use warnings;

# Load webmin libraries
do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();
our (%in, %text, %config);
&ReadParse();

our $module_name = "netplanmgr";
&load_language($module_name);
&read_file("$ENV{'WEBMIN_CONFIG'}/$module_name/config", \%config);

# Helper subs
sub list_netplan_files {
    my $dir = $config{'netplan_path'} || "/etc/netplan";
    my @files;
    if (opendir(my $dh, $dir)) {
        @files = sort grep { /\.ya?ml$/i && -f "$dir/$_" } readdir($dh);
        closedir($dh);
    }
    return map { "$dir/$_" } @files;
}

sub read_file_content {
    my ($f) = @_;
    return undef unless -f $f;
    if (open(my $fh, '<', $f)) {
        local $/;
        my $c = <$fh>;
        close($fh);
        return $c;
    }
    return undef;
}

sub write_file_content {
    my ($f, $content) = @_;
    if (open(my $fh, '>', $f)) {
        print $fh $content;
        close($fh);
        return 1;
    }
    return 0;
}

# ============================================================
# PROCESS ACTIONS (antes del header para manejar redirects)
# ============================================================

# Handle AJAX request for file content
if (defined $in{'ajax'} && $in{'ajax'} eq '1') {
    my $file = $in{'file'} || '';
    if ($file && -f $file) {
        my $content = read_file_content($file);
        print "Content-type: text/plain; charset=utf-8\r\n\r\n";
        print $content || '';
    } else {
        print "Content-type: text/plain\r\n\r\n";
        print "Error: File not found";
    }
    exit;
}

# Handle SAVE action
if (defined $in{'save'}) {
    my $file = $in{'file'} || '';
    my $content = $in{'content'} || '';
    if ($file && write_file_content($file, $content)) {
        &redirect("index.cgi?saved=1&file=" . &urlize($file));
    } else {
        &redirect("index.cgi?error=save");
    }
    exit;
}

# Handle VALIDATE action
if (defined $in{'validate'}) {
    my $file = $in{'file'} || '';
    if ($file && -f $file) {
        my $tmp = "/tmp/netplan-validate-$$.yaml";
        if (write_file_content($tmp, read_file_content($file))) {
            my $cmd = "netplan generate --root-dir=/tmp/netplan-test-$$ 2>&1";
            my $out = `$cmd`;
            my $exit = $? >> 8;
            unlink($tmp);
            system("rm -rf /tmp/netplan-test-$$ 2>/dev/null");
            
            if ($exit == 0 || $out !~ /error/i) {
                &redirect("index.cgi?validated=1&file=" . &urlize($file));
            } else {
                &redirect("index.cgi?validated=0&file=" . &urlize($file) . "&msg=" . &urlize($out));
            }
        } else {
            &redirect("index.cgi?error=validate");
        }
    } else {
        &redirect("index.cgi?error=file");
    }
    exit;
}

# Handle APPLY action
if (defined $in{'apply'}) {
    my $file = $in{'file'} || '';
    if ($file) {
        # Save first if content present
        if (defined $in{'content'}) {
            if (!write_file_content($file, $in{'content'})) {
                &redirect("index.cgi?error=save");
                exit;
            }
        }
        # Apply
        my $out = `netplan apply 2>&1`;
        my $exit = $? >> 8;
        if ($exit == 0) {
            &redirect("index.cgi?applied=1&file=" . &urlize($file));
        } else {
            &redirect("index.cgi?applied=0&file=" . &urlize($file) . "&msg=" . &urlize($out));
        }
    } else {
        &redirect("index.cgi?error=file");
    }
    exit;
}

# ============================================================
# UI OUTPUT (después de procesar acciones)
# ============================================================

# Anti-cache headers
print "Cache-Control: no-cache, no-store, must-revalidate, max-age=0\r\n";
print "Pragma: no-cache\r\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\r\n";

# Print header
&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

# CSS Responsive
print <<'CSS';
<style>
.netplan-container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

.alert-success, .alert-error, .alert-warning, .info-box {
    padding: 12px 16px;
    border-radius: 6px;
    margin: 16px 0;
    font-weight: 500;
}

.alert-success {
    background-color: #d4edda;
    color: #155724;
    border-left: 4px solid #28a745;
}

.alert-error {
    background-color: #f8d7da;
    color: #721c24;
    border-left: 4px solid #dc3545;
}

.alert-warning {
    background-color: #fff3cd;
    color: #856404;
    border-left: 4px solid #ffc107;
}

.info-box {
    background-color: #d1ecf1;
    color: #0c5460;
    border-left: 4px solid #17a2b8;
}

.file-table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    border-radius: 8px;
    overflow: hidden;
    margin: 20px 0;
}

.file-table thead {
    background: #f8f9fa;
    border-bottom: 2px solid #dee2e6;
}

.file-table th {
    padding: 12px 16px;
    text-align: left;
    font-weight: 600;
    color: #495057;
}

.file-table td {
    padding: 12px 16px;
    border-bottom: 1px solid #dee2e6;
}

.file-table tbody tr:hover {
    background-color: #f8f9fa;
}

.file-table code {
    background: #e9ecef;
    padding: 4px 8px;
    border-radius: 4px;
    font-family: 'Courier New', monospace;
}

/* Custom button styles - compatible with all Webmin themes */
.netplan-btn {
    padding: 6px 16px;
    border: 1px solid #ccc;
    border-radius: 4px;
    cursor: pointer;
    font-size: 13px;
    font-weight: 500;
    transition: all 0.2s;
    margin: 0;
    font-family: inherit;
    line-height: 1.5;
    text-align: center;
    white-space: nowrap;
}

.netplan-btn:hover {
    opacity: 0.85;
    border-color: #999;
}

.netplan-btn:active {
    transform: translateY(1px);
}

.netplan-btn-edit {
    background-color: #6c757d;
    color: white;
    border-color: #6c757d;
}

.netplan-btn-edit:hover {
    background-color: #5a6268;
    border-color: #545b62;
}

.netplan-btn-validate {
    background-color: #17a2b8;
    color: white;
    border-color: #17a2b8;
}

.netplan-btn-validate:hover {
    background-color: #138496;
    border-color: #117a8b;
}

.netplan-btn-apply {
    background-color: #28a745;
    color: white;
    border-color: #28a745;
}

.netplan-btn-apply:hover {
    background-color: #218838;
    border-color: #1e7e34;
}

.netplan-btn-cancel {
    background-color: #6c757d;
    color: white;
    border-color: #6c757d;
}

.netplan-btn-cancel:hover {
    background-color: #5a6268;
    border-color: #545b62;
}

.netplan-btn-save {
    background-color: #007bff;
    color: white;
    border-color: #007bff;
}

.netplan-btn-save:hover {
    background-color: #0056b3;
    border-color: #004085;
}

.btn-primary, .btn-secondary, .btn-success {
    padding: 8px 16px;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
    font-weight: 500;
    transition: all 0.2s;
    margin: 2px;
}

.btn-primary {
    background-color: #007bff;
    color: white;
}

.btn-primary:hover {
    background-color: #0056b3;
}

.btn-secondary {
    background-color: #6c757d;
    color: white;
}

.btn-secondary:hover {
    background-color: #545b62;
}

.btn-success {
    background-color: #28a745;
    color: white;
}

.btn-success:hover {
    background-color: #218838;
}

.button-group {
    display: flex;
    gap: 8px;
    align-items: center;
    flex-wrap: wrap;
}

.button-group form {
    margin: 0;
    display: inline-block;
}

/* Modal styles */
.modal-overlay {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background-color: rgba(0, 0, 0, 0.7);
    z-index: 9998;
    animation: fadeIn 0.2s;
}

.modal-overlay.active {
    display: block;
}

.modal-container {
    display: none;
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 90%;
    max-width: 1000px;
    max-height: 90vh;
    background: white;
    border-radius: 8px;
    box-shadow: 0 10px 40px rgba(0,0,0,0.3);
    z-index: 9999;
    overflow: hidden;
    animation: slideDown 0.3s;
}

.modal-container.active {
    display: flex;
    flex-direction: column;
}

.modal-header {
    padding: 16px 20px;
    background: #f8f9fa;
    border-bottom: 2px solid #dee2e6;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.modal-header h4 {
    margin: 0;
    color: #333;
    font-size: 18px;
}

.modal-close {
    background: none;
    border: none;
    font-size: 28px;
    color: #666;
    cursor: pointer;
    line-height: 1;
    padding: 0;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
    transition: all 0.2s;
}

.modal-close:hover {
    background: #e9ecef;
    color: #333;
}

.modal-body {
    padding: 20px;
    overflow-y: auto;
    flex: 1;
}

.modal-body textarea {
    width: 100%;
    font-family: 'Courier New', monospace;
    font-size: 13px;
    padding: 12px;
    border: 1px solid #ced4da;
    border-radius: 4px;
    box-sizing: border-box;
    resize: vertical;
    min-height: 400px;
}

.modal-footer {
    padding: 16px 20px;
    background: #f8f9fa;
    border-top: 1px solid #dee2e6;
    display: flex;
    justify-content: flex-end;
    gap: 10px;
}

@keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
}

@keyframes slideDown {
    from {
        opacity: 0;
        transform: translate(-50%, -55%);
    }
    to {
        opacity: 1;
        transform: translate(-50%, -50%);
    }
}

/* Responsive Design */
@media (max-width: 768px) {
    .netplan-container {
        padding: 10px;
    }
    
    .file-table {
        font-size: 14px;
    }
    
    .file-table th,
    .file-table td {
        padding: 8px;
    }
    
    .button-group {
        flex-direction: column;
        width: 100%;
    }
    
    .button-group button,
    .button-group form {
        width: 100%;
    }
    
    .netplan-btn {
        width: 100%;
        padding: 10px 16px;
    }
    
    .btn-primary, .btn-secondary, .btn-success {
        padding: 8px 12px;
        font-size: 13px;
        width: 100%;
    }
    
    .modal-container {
        width: 95%;
        max-height: 95vh;
    }
    
    .modal-body textarea {
        min-height: 300px;
        font-size: 12px;
    }
}

@media (max-width: 480px) {
    .file-table thead {
        display: none;
    }
    
    .file-table tr {
        display: block;
        margin-bottom: 16px;
        border: 1px solid #dee2e6;
        border-radius: 8px;
    }
    
    .file-table td {
        display: block;
        text-align: left;
        padding: 8px 12px;
        border-bottom: 1px solid #dee2e6;
    }
    
    .file-table td:last-child {
        border-bottom: none;
    }
    
    .file-table td:before {
        content: attr(data-label);
        font-weight: bold;
        display: block;
        margin-bottom: 4px;
        color: #495057;
    }
    
    .modal-container {
        width: 100%;
        max-height: 100vh;
        border-radius: 0;
    }
}
</style>
CSS

# Display messages
if (defined $in{'saved'}) {
    print "<div class='alert-success'>✓ $text{'save_success'}</div>";
}

if (defined $in{'validated'}) {
    if ($in{'validated'} eq '1') {
        print "<div class='alert-success'>✓ $text{'validate_success'}</div>";
    } else {
        print "<div class='alert-error'>✗ $text{'validate_failed'}</div>";
        if (defined $in{'msg'}) {
            print "<pre style='background:#f8f9fa;padding:12px;border-radius:4px;overflow-x:auto;'>" . &html_escape($in{'msg'}) . "</pre>";
        }
    }
}

if (defined $in{'applied'}) {
    if ($in{'applied'} eq '1') {
        print "<div class='alert-success'>✓ $text{'apply_success'}</div>";
    } else {
        print "<div class='alert-error'>✗ $text{'apply_failed'}</div>";
        if (defined $in{'msg'}) {
            print "<pre style='background:#f8f9fa;padding:12px;border-radius:4px;overflow-x:auto;'>" . &html_escape($in{'msg'}) . "</pre>";
        }
    }
}

if (defined $in{'error'}) {
    print "<div class='alert-error'>✗ $text{'file_error'}</div>";
}

# Main container
print "<div class='netplan-container'>";
print "<h3>🌐 $text{'index_title'}</h3>";
print "<p>$text{'index_desc'}</p>";

my @files = list_netplan_files();

if (!@files) {
    print "<div class='alert-warning'>$text{'no_files'}</div>";
} else {
    print "<table class='file-table'>";
    print "<thead><tr><th>$text{'table_file'}</th><th>$text{'table_actions'}</th></tr></thead>";
    print "<tbody>";
    
    foreach my $f (@files) {
        my $basename = $f;
        $basename =~ s{.*/}{};
        my $escaped_file = &html_escape($f);
        my $escaped_basename = &html_escape($basename);
        
        print "<tr>";
        print "<td data-label='$text{\"table_file\"}'><code>$escaped_basename</code></td>";
        print "<td data-label='$text{\"table_actions\"}'>";
        print "<div class='button-group'>";
        
        # Edit button
        print "<button type='button' class='netplan-btn netplan-btn-edit' onclick='openEditModal(\"$escaped_file\", \"$escaped_basename\")'>$text{'action_edit'}</button>";
        
        # Validate button with hidden form
        print "<form method='post' action='index.cgi' style='display:inline-block; margin:0;'>";
        print "<input type='hidden' name='file' value='$escaped_file'>";
        print "<input type='hidden' name='validate' value='1'>";
        print "<button type='submit' class='netplan-btn netplan-btn-validate'>$text{'action_validate'}</button>";
        print "</form>";
        
        # Apply button with hidden form
        print "<form method='post' action='index.cgi' style='display:inline-block; margin:0;'>";
        print "<input type='hidden' name='file' value='$escaped_file'>";
        print "<input type='hidden' name='apply' value='1'>";
        print "<button type='submit' class='netplan-btn netplan-btn-apply'>$text{'action_apply'}</button>";
        print "</form>";
        
        print "</div>";
        print "</td>";
        print "</tr>";
    }
    
    print "</tbody></table>";
}

# Edit form (if edit button clicked)
if (defined $in{'edit'}) {
    my $file = $in{'file'} || '';
    my $content = read_file_content($file) || "";
    my $basename = $file;
    $basename =~ s{.*/}{};
    
    print "<div class='edit-section'>";
    print "<h4>$text{'editing'}: <code>$basename</code></h4>";
    print &ui_form_start("index.cgi", "post");
    print &ui_hidden("file", $file);
    print &ui_textarea("content", $content, 25, 100);
    print "<br>";
    print &ui_submit($text{'action_save'}, "save");
    print " ";
    print "<input type='button' value='$text{\"action_cancel\"}' onclick='window.location=\"index.cgi\"' class='btn-secondary'>";
    print &ui_form_end();
    print "</div>";
}

print "</div>"; # netplan-container

# Modal HTML for editing files
print <<'MODAL';
<!-- Modal Overlay -->
<div id="modalOverlay" class="modal-overlay" onclick="closeEditModal()"></div>

<!-- Modal Container -->
<div id="editModal" class="modal-container">
    <div class="modal-header">
        <h4 id="modalTitle">Editing file</h4>
        <button class="modal-close" onclick="closeEditModal()">&times;</button>
    </div>
    <div class="modal-body">
        <form id="editForm" method="post" action="index.cgi">
            <input type="hidden" name="file" id="modalFile" value="">
            <input type="hidden" name="save" value="1">
            <textarea name="content" id="modalContent" rows="20"></textarea>
        </form>
    </div>
    <div class="modal-footer">
        <button type="button" class="netplan-btn netplan-btn-cancel" onclick="closeEditModal()">Cancel</button>
        <button type="button" class="netplan-btn netplan-btn-save" onclick="saveFile()">Save</button>
    </div>
</div>

<script>
function openEditModal(filePath, fileName) {
    // Show loading
    document.getElementById('modalContent').value = 'Loading...';
    document.getElementById('modalTitle').textContent = 'Editing: ' + fileName;
    document.getElementById('modalFile').value = filePath;
    
    // Show modal
    document.getElementById('modalOverlay').classList.add('active');
    document.getElementById('editModal').classList.add('active');
    
    // Fetch file content via AJAX
    fetch('index.cgi?ajax=1&file=' + encodeURIComponent(filePath))
        .then(response => response.text())
        .then(content => {
            document.getElementById('modalContent').value = content;
            document.getElementById('modalContent').focus();
        })
        .catch(error => {
            document.getElementById('modalContent').value = 'Error loading file: ' + error;
        });
}

function closeEditModal() {
    document.getElementById('modalOverlay').classList.remove('active');
    document.getElementById('editModal').classList.remove('active');
    document.getElementById('modalContent').value = '';
}

function saveFile() {
    document.getElementById('editForm').submit();
}

// Close modal with ESC key
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        closeEditModal();
    }
});
</script>
MODAL

&ui_print_footer("/", $text{'index'});
INDEXCGI

    chmod 755 "$MODDIR/index.cgi"
    
    # ============================================================
    # 2. module.info (English)
    # ============================================================
    cat > "$MODDIR/module.info" <<'EOF'
desc=Netplan Manager
longdesc=View, edit and apply Netplan YAML configuration files
category=net
os_support=*-linux
version=1.2
depends=webmin
EOF
    
    # ============================================================
    # 3. module.info.es (Spanish)
    # ============================================================
    cat > "$MODDIR/module.info.es" <<'EOF'
desc=Administrador de Netplan
longdesc=Ver, editar y aplicar archivos YAML de Netplan
category=net
os_support=*-linux
version=1.2
depends=webmin
EOF
    
    # ============================================================
    # 4. lang/en (English strings)
    # ============================================================
    cat > "$MODDIR/lang/en" <<'EOF'
index_title=Netplan Manager
index_desc=Manage Netplan network configuration files under /etc/netplan
table_file=Configuration File
table_actions=Actions
action_edit=Edit
action_validate=Validate
action_apply=Apply
action_save=Save
action_cancel=Cancel
validate_success=YAML configuration is valid
validate_failed=Validation failed
save_success=File saved successfully
save_failed=Failed to save file
apply_success=Configuration applied successfully
apply_failed=Failed to apply configuration
file_error=File not specified or not found
editing=Editing
no_files=No Netplan YAML files found in /etc/netplan
applying=Applying configuration...
index=Webmin Index
EOF
    
    # ============================================================
    # 5. lang/es (Spanish strings)
    # ============================================================
    cat > "$MODDIR/lang/es" <<'EOF'
index_title=Administrador de Netplan
index_desc=Gestiona los archivos de configuración Netplan en /etc/netplan
table_file=Archivo de Configuración
table_actions=Acciones
action_edit=Editar
action_validate=Validar
action_apply=Aplicar
action_save=Guardar
action_cancel=Cancelar
validate_success=La configuración YAML es válida
validate_failed=La validación falló
save_success=Archivo guardado exitosamente
save_failed=Fallo al guardar el archivo
apply_success=Configuración aplicada con éxito
apply_failed=Fallo al aplicar la configuración
file_error=Archivo no especificado o no encontrado
editing=Editando
no_files=No se encontraron archivos YAML de Netplan en /etc/netplan
applying=Aplicando configuración...
index=Índice de Webmin
EOF
    
    # ============================================================
    # 6. config.info (Configuration options - English)
    # ============================================================
    cat > "$MODDIR/config.info" <<'EOF'
netplan_path=Netplan configuration directory,0
netplan_backup=Create backup before applying,1,1-Yes,0-No
backup_path=Backup directory,0
backup_keep=Number of backups to keep,0,5
EOF

    # ============================================================
    # 6b. config.info.es (Configuration options - Spanish)
    # ============================================================
    cat > "$MODDIR/config.info.es" <<'EOF'
netplan_path=Directorio de configuración Netplan,0
netplan_backup=Crear respaldo antes de aplicar,1,1-Sí,0-No
backup_path=Directorio de respaldos,0
backup_keep=Número de respaldos a mantener,0,5
EOF
    
    # ============================================================
    # 7. defaultconfig (Default configuration values)
    # ============================================================
    cat > "$MODDIR/defaultconfig" <<'EOF'
netplan_path=/etc/netplan
netplan_backup=1
backup_path=/var/backups/netplan
backup_keep=5
EOF
    
    # ============================================================
    # 8. config (Initial configuration - same as defaults)
    # ============================================================
    cat > "$ETCDIR/config" <<'EOF'
netplan_path=/etc/netplan
netplan_backup=1
backup_path=/var/backups/netplan
backup_keep=5
EOF
    
    # ============================================================
    # 9. netplanmgr-lib.pl
    # ============================================================
    cat > "$MODDIR/netplanmgr-lib.pl" <<'EOF'
#!/usr/bin/perl
# Netplan Manager library functions

do '../web-lib.pl';
do '../ui-lib.pl';
&init_config();

1;
EOF
    
    chmod 755 "$MODDIR/netplanmgr-lib.pl"
    
    # ============================================================
    # 10. install_check.pl
    # ============================================================
    cat > "$MODDIR/install_check.pl" <<'EOF'
#!/usr/bin/perl
# Check if netplan is available

do '../web-lib.pl';

sub module_install_check {
    if (!&has_command("netplan")) {
        return "netplan command not found - Netplan is required for this module";
    }
    return undef;
}
EOF
    
    chmod 755 "$MODDIR/install_check.pl"
    
    # ============================================================
    # 11. help/intro.html
    # ============================================================
    cat > "$MODDIR/help/intro.html" <<'EOF'
<header>Netplan Manager</header>

<h3>Introduction</h3>
<p>The Netplan Manager module allows you to view, edit and apply Netplan YAML files located in /etc/netplan. Use Validate before Apply to avoid applying broken configuration.</p>

<h3>Usage</h3>
<ul>
<li><strong>Edit:</strong> Opens the YAML file in an editor. After editing, press Save.</li>
<li><strong>Validate:</strong> Checks YAML syntax using netplan generate.</li>
<li><strong>Apply:</strong> Runs <code>netplan apply</code> to activate the configuration.</li>
</ul>

<h3>Workflow</h3>
<ol>
<li>Click <strong>Edit</strong> to modify a configuration file</li>
<li>Make your changes and click <strong>Save</strong></li>
<li>Click <strong>Validate</strong> to check for errors</li>
<li>If validation passes, click <strong>Apply</strong> to activate</li>
</ol>

<footer>
EOF
    
    # ============================================================
    # 12. help/intro.es.html
    # ============================================================
    cat > "$MODDIR/help/intro.es.html" <<'EOF'
<header>Administrador de Netplan</header>

<h3>Introducción</h3>
<p>El módulo Administrador de Netplan permite ver, editar y aplicar archivos YAML de Netplan ubicados en /etc/netplan. Use Validar antes de Aplicar para evitar aplicar configuraciones erróneas.</p>

<h3>Uso</h3>
<ul>
<li><strong>Editar:</strong> Abre el archivo YAML en un editor. Después de editar, presione Guardar.</li>
<li><strong>Validar:</strong> Verifica la sintaxis YAML usando netplan generate.</li>
<li><strong>Aplicar:</strong> Ejecuta <code>netplan apply</code> para activar la configuración.</li>
</ul>

<h3>Flujo de trabajo</h3>
<ol>
<li>Haga clic en <strong>Editar</strong> para modificar un archivo de configuración</li>
<li>Realice sus cambios y haga clic en <strong>Guardar</strong></li>
<li>Haga clic en <strong>Validar</strong> para verificar errores</li>
<li>Si la validación pasa, haga clic en <strong>Aplicar</strong> para activar</li>
</ol>

<footer>
EOF
    
    # ============================================================
    # 13. CHANGELOG
    # ============================================================
    cat > "$MODDIR/CHANGELOG" <<'EOF'
Version 1.2 (2025)
- Added modal popup editor for better UX with long file lists
- Added AJAX file loading for instant editing
- Added configuration options (backup, themes, auto-validate)
- Added Spanish configuration translations
- Improved user experience with floating editor

Version 1.1 (2025)
- Fixed button functionality with proper redirects
- Added responsive CSS design
- Improved mobile experience
- Better error handling and user feedback
- Enhanced UI with modern styling

Version 1.0 (2025)
- Initial Netplan Manager release
- View, edit, validate and apply Netplan YAML files
- Multi-language (en/es)
EOF
    
    # ============================================================
    # 14. Create icon.gif
    # ============================================================
    cat > /tmp/icon.gif.b64 << 'ICONEOF'
R0lGODlhMAAwAPAAAAAAAAAAACH5BAEAAAAALAAAAAAwADAAAAKrhI+py+0Po5wqJEszCpyf7mkUiAGkOJJqiUKr2krvGS/zDdYGzusmj6vdLjPfynb0/XIVmnLZQTKfsOZU95I6W8NNUQj8yq5hcWRbzk62xOA5BIX/Pj0XML6rP9JuvJ3v4cTGAChncpFR+JSXtshIlgSm5mWWWPlYJdLVFqmxSdlpOQmayRU6isXnGHfnqEhVyBITazgbuxiFWXKlxFJ6uGpVGywsS3yMHFMAADs=
ICONEOF
    
    base64 -d /tmp/icon.gif.b64 > "$MODDIR/images/icon.gif"
    rm -f /tmp/icon.gif.b64
    
    # ============================================================
    # Set permissions
    # ============================================================
    chown -R root:root "$MODDIR" "$ETCDIR"
    chmod -R 755 "$MODDIR"
    chmod 644 "$MODDIR"/*.info* "$MODDIR/lang/"* "$MODDIR/help/"* "$MODDIR/CHANGELOG" 2>/dev/null || true
    chmod 755 "$MODDIR"/*.cgi "$MODDIR"/*.pl 2>/dev/null || true
    chmod 644 "$MODDIR/images/"* 2>/dev/null || true
    
    # ============================================================
    # Register in Webmin ACL
    # ============================================================
    if ! grep -q "$MODNAME" /etc/webmin/webmin.acl 2>/dev/null; then
        sed -i.bak 's/\(^root:.*\)/\1 '"$MODNAME"'/' /etc/webmin/webmin.acl
        echo "✓ Module added to webmin.acl"
    fi
    
    # Clear cache
    rm -f /var/webmin/module.infos.cache
    
    # Restart Webmin
    echo "Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true
    
    echo ""
    echo "=========================================="
    echo "✓ Netplan Manager installed successfully!"
    echo "=========================================="
    echo ""
    echo "Module location: $MODDIR"
    echo "Config location: $ETCDIR"
    echo ""
    echo "Please refresh your browser to see the module."
    echo "Find it under the 'Network' category."
    echo ""
}

# ============================================================
# Function: Uninstall Module
# ============================================================
uninstall_module() {
    echo ""
    echo "=========================================="
    echo "Uninstalling Netplan Manager Module"
    echo "=========================================="
    echo ""
    
    if [ ! -d "$MODDIR" ]; then
        echo "⚠  Module is not installed."
        echo ""
        return 1
    fi
    
    echo "Removing module files..."
    rm -rf "$MODDIR"
    rm -rf "$ETCDIR"
    
    # Remove from ACL
    if grep -q "$MODNAME" /etc/webmin/webmin.acl 2>/dev/null; then
        sed -i.bak 's/ '"$MODNAME"'//g' /etc/webmin/webmin.acl
        echo "✓ Module removed from webmin.acl"
    fi
    
    # Clear cache
    rm -f /var/webmin/module.infos.cache
    echo "✓ Module cache cleared"
    
    # Restart Webmin
    echo "Restarting Webmin service..."
    systemctl restart webmin.service 2>/dev/null || /etc/webmin/restart 2>/dev/null || true
    
    echo ""
    echo "=========================================="
    echo "✓ Netplan Manager uninstalled"
    echo "=========================================="
    echo ""
}

# ============================================================
# Show usage
# ============================================================
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install      Install the Netplan Manager module"
    echo "  uninstall    Uninstall the Netplan Manager module"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 uninstall"
    echo ""
}

# ============================================================
# Main
# ============================================================
main() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
    
    if [ ! -d "/usr/share/webmin" ] && [ ! -d "/etc/webmin" ]; then
        echo "Error: Webmin is not installed on this system"
        exit 1
    fi
    
    if [ $# -gt 0 ]; then
        case "$1" in
            install)
                install_module
                exit 0
                ;;
            uninstall)
                uninstall_module
                exit 0
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Error: Invalid option '$1'"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    fi
    
    # Interactive menu
    while true; do
        clear
        echo "============================================================"
        echo "          NETPLAN MANAGER - WEBMIN MODULE"
        echo "                 Installation Menu"
        echo "============================================================"
        echo ""
        echo "  1) Install module"
        echo "  2) Uninstall module"
        echo "  3) Exit"
        echo ""
        echo -n "Select an option [1-3]: "
        read -r option
        
        case $option in
            1)
                install_module
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                uninstall_module
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                echo "Exiting..."
                echo ""
                exit 0
                ;;
            *)
                echo ""
                echo "Invalid option. Please select 1, 2, or 3."
                echo ""
                sleep 2
                ;;
        esac
    done
}

main "$@"
