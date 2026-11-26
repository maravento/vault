<?php
// Interface language: Spanish when the browser prefers Spanish, English for any other language.
// The texts of the code are written in Spanish; lang_en.php holds the English version of each one.
// FILE: app/i18n.php

// 'es' or 'en', from the Accept-Language header: the language with the highest q wins
function lang(): string
{
    static $lang = null;
    if ($lang !== null) {
        return $lang;
    }
    $best = '';
    $bestq = -1.0;
    foreach (explode(',', (string) ($_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? '')) as $part) {
        $bits = explode(';', trim($part));
        $tag = strtolower(trim($bits[0]));
        $q = 1.0;
        if (isset($bits[1]) && preg_match('/q=([0-9.]+)/', $bits[1], $m)) {
            $q = (float) $m[1];
        }
        if ($tag !== '' && $tag !== '*' && $q > 0 && $q > $bestq) {
            $best = $tag;
            $bestq = $q;
        }
    }
    $lang = ($best === 'es' || str_starts_with($best, 'es-')) ? 'es' : 'en';
    return $lang;
}

// Text of the interface in the language of the browser; a text without translation stays as written
function t(string $es): string
{
    static $en = null;
    if (lang() === 'es') {
        return $es;
    }
    $en ??= require __DIR__ . '/lang_en.php';
    return $en[$es] ?? $es;
}
