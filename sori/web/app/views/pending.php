<?php
// Placeholder page for modules not implemented yet
// FILE: app/views/pending.php
try {
    $n = (int) tenant()->query('SELECT COUNT(*) FROM `' . $mod['table'] . '`')->fetchColumn();
} catch (PDOException) {
    $n = null;
}
?>
<div class="content-area">
    <a class="btn-small" href="/"><?= e(t('← Volver')) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t($mod['name'])) ?></h2>
    <p class="muted"><?= e(t('🚧 Módulo en construcción.')) ?></p>
    <p class="muted">
        <?= e(t('Datos migrados:')) ?> <?= $n === null ? e(t('la tabla no existe')) : num($n) . ' ' . e(t('registros')) ?>
        <?= e(t('en')) ?> <code><?= e($mod['table']) ?></code>.
    </p>
</div>
