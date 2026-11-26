<?php
// Platform administration: list of clients
// FILE: app/views/admin.php
?>
<div class="content-area">
    <h2><i class="fas fa-key"></i> <?= e(t('Clientes')) ?></h2>
    <div class="table-wrap">
    <table class="content-table">
        <thead><tr><th><?= e(t('Código')) ?></th><th><?= e(t('Cliente')) ?></th><th><?= e(t('Usuarios')) ?></th><th><?= e(t('Estado')) ?></th><th><?= e(t('Creado')) ?></th></tr></thead>
        <tbody>
        <?php foreach ($clientes as $c): ?>
            <tr>
                <td><?= e($c['slug']) ?></td>
                <td><?= e($c['nombre']) ?></td>
                <td><?= (int) $c['usuarios'] ?></td>
                <td><?= e(t((int) $c['activo'] ? 'Activo' : 'Inactivo')) ?></td>
                <td><?= e($c['creado']) ?></td>
            </tr>
        <?php endforeach; ?>
        <?php if (!$clientes): ?>
            <tr><td colspan="5"><?= e(t('No hay clientes. Cree uno con la herramienta de migración.')) ?></td></tr>
        <?php endif; ?>
        </tbody>
    </table>
    </div>
</div>
