<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Test basic PHP
echo "PHP is working...<br>";

// Test file operations
$test_file = dirname(__FILE__) . '/test_write.txt';
if (file_put_contents($test_file, 'test')) {
    echo "File write OK<br>";
    unlink($test_file);
} else {
    echo "File write FAILED<br>";
}

// Test original sqstat
include_once("sqstat.class.php");
echo "Class loaded OK<br>";

$squidclass = new squidstat();
echo "Object created OK<br>";
?>
