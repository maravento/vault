<?php
// Page layout: header, user area and footer shared by every view
// FILE: app/views/layout.php
$who = user();
?>
<!DOCTYPE html>
<html lang="<?= lang() ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="robots" content="noindex, nofollow">
    <meta name="theme-color" content="#1e3a5f">
    <title>SORI ERP · <?= e(t('Sistema de Operaciones y Recursos Integrales')) ?></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
    <link rel="stylesheet" href="/assets/sori.css">
</head>
<body>
<div class="main-container">
    <div class="header">
        <div class="logo"><i class="fas fa-cubes"></i></div>
        <div class="title-group">
            <h1>SORI ERP</h1>
            <div class="subtitle"><?= e(t('Sistema de Operaciones y Recursos Integrales')) ?></div>
        </div>
        <?php if ($who): ?>
        <form class="user-box" method="post" action="/logout">
            <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
            <span><i class="fas fa-user"></i> <?= e($who['nombre']) ?></span>
            <button type="submit" class="btn-small"><?= e(t('Salir')) ?></button>
        </form>
        <?php endif; ?>
    </div>

    <?= $content ?>

    <div class="footer-sori">SORI ERP · maravento.com</div>
</div>
<script src="/assets/sori.js"></script>
</body>
</html>
