<?php
// Login form
// FILE: app/views/login.php
?>
<form class="login-card" method="post" action="/login" autocomplete="off">
    <h2><?= e(t('Acceso al sistema')) ?></h2>
    <?php if (!empty($error)): ?>
        <p class="error"><?= e($error) ?></p>
    <?php endif; ?>
    <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
    <input type="text" name="usuario" placeholder="<?= e(t('Usuario')) ?>" required autofocus maxlength="30">
    <input type="password" name="clave" placeholder="<?= e(t('Contraseña')) ?>" required maxlength="200">
    <button type="submit" class="btn-main"><?= e(t('INGRESAR')) ?></button>
</form>
